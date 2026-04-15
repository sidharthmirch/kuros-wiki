#!/usr/bin/env python3
"""Track upstream changes and emit combined reports/suggestions."""

from __future__ import annotations

import argparse
import copy
import fnmatch
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib import error, parse, request

EXIT_OK = 0
EXIT_CHANGES = 2
EXIT_FAILURE = 10


class TrackerError(Exception):
    def __init__(self, message: str, code: int = EXIT_FAILURE):
        super().__init__(message)
        self.code = code


class GitHubAPIError(TrackerError):
    def __init__(self, message: str, status_code: int, body: str | None = None):
        super().__init__(message, EXIT_FAILURE + 1)
        self.status_code = status_code
        self.body = body or ""


@dataclass
class SourceResult:
    name: str
    repo: str
    branch: str
    baseline_sha: str
    head_sha: str
    head_date: str
    head_message: str
    new_commits: list[dict[str, Any]]
    changed_files: list[str]
    tracked_files: list[str]
    escalated_files: list[str]
    conflict_files: list[str]
    warnings: list[str]
    scan_status: str
    file_latest_sha: dict[str, str]
    commit_file_map: dict[str, list[str]]


class GitHubClient:
    def __init__(self, token: str | None = None, timeout: int = 20):
        self.token = token
        self.timeout = timeout

    def get_json(self, url: str, params: dict[str, Any] | None = None) -> Any:
        if params:
            query = parse.urlencode(params)
            url = f"{url}?{query}"

        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "kuros-upstream-tracker",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"

        req = request.Request(url, headers=headers)
        try:
            with request.urlopen(req, timeout=self.timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            msg = f"GitHub API request failed ({exc.code}) for {url}"
            raise GitHubAPIError(msg, exc.code, body) from exc
        except error.URLError as exc:
            raise TrackerError(f"GitHub API request error for {url}: {exc}", EXIT_FAILURE + 2) from exc

    def get_head_commit(self, repo: str, branch: str) -> dict[str, str]:
        data = self.get_json(f"https://api.github.com/repos/{repo}/commits/{branch}")
        return {
            "sha": data["sha"],
            "date": data["commit"]["committer"]["date"],
            "message": data["commit"]["message"].splitlines()[0],
        }

    def compare(self, repo: str, base: str, head: str) -> dict[str, Any]:
        return self.get_json(f"https://api.github.com/repos/{repo}/compare/{base}...{head}")

    def list_commits(self, repo: str, branch: str, per_page: int) -> list[dict[str, Any]]:
        return self.get_json(
            f"https://api.github.com/repos/{repo}/commits",
            params={"sha": branch, "per_page": per_page},
        )

    def get_commit(self, repo: str, sha: str) -> dict[str, Any]:
        return self.get_json(f"https://api.github.com/repos/{repo}/commits/{sha}")


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_structured_file(path: Path) -> Any:
    text = path.read_text()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    try:
        import yaml  # type: ignore
    except ImportError as exc:
        raise TrackerError(
            f"Unable to parse {path}. Install PyYAML or use JSON-compatible YAML.",
            EXIT_FAILURE + 3,
        ) from exc

    data = yaml.safe_load(text)
    if data is None:
        raise TrackerError(f"{path} is empty", EXIT_FAILURE + 3)
    return data


def ensure_dict(value: Any, name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise TrackerError(f"{name} must be an object", EXIT_FAILURE + 4)
    return value


def ensure_list(value: Any, name: str) -> list[Any]:
    if not isinstance(value, list):
        raise TrackerError(f"{name} must be a list", EXIT_FAILURE + 4)
    return value


def validate_config(config: dict[str, Any]) -> None:
    if config.get("version") != 1:
        raise TrackerError("config.version must be 1", EXIT_FAILURE + 4)

    sources = ensure_dict(config.get("sources"), "config.sources")
    if not sources:
        raise TrackerError("config.sources must contain at least one source", EXIT_FAILURE + 4)

    for source_name, source in sources.items():
        source_obj = ensure_dict(source, f"config.sources.{source_name}")
        for field in ("repo", "branch", "enabled"):
            if field not in source_obj:
                raise TrackerError(f"config.sources.{source_name}.{field} is required", EXIT_FAILURE + 4)
        if not isinstance(source_obj["repo"], str) or "/" not in source_obj["repo"]:
            raise TrackerError(f"config.sources.{source_name}.repo must be owner/name", EXIT_FAILURE + 4)
        if not isinstance(source_obj["branch"], str):
            raise TrackerError(f"config.sources.{source_name}.branch must be a string", EXIT_FAILURE + 4)
        if not isinstance(source_obj["enabled"], bool):
            raise TrackerError(f"config.sources.{source_name}.enabled must be boolean", EXIT_FAILURE + 4)

    ownership_rules = ensure_list(config.get("ownership_rules", []), "config.ownership_rules")
    for idx, rule in enumerate(ownership_rules):
        rule_obj = ensure_dict(rule, f"config.ownership_rules[{idx}]")
        for field in ("pattern", "owner", "mode"):
            if field not in rule_obj:
                raise TrackerError(f"config.ownership_rules[{idx}].{field} is required", EXIT_FAILURE + 4)
        if rule_obj["mode"] not in {"track", "escalate"}:
            raise TrackerError(f"config.ownership_rules[{idx}].mode must be track/escalate", EXIT_FAILURE + 4)

    settings = ensure_dict(config.get("settings"), "config.settings")
    for field in ("max_commits", "report_limit", "default_owner"):
        if field not in settings:
            raise TrackerError(f"config.settings.{field} is required", EXIT_FAILURE + 4)
    if not isinstance(settings["max_commits"], int) or settings["max_commits"] <= 0:
        raise TrackerError("config.settings.max_commits must be positive integer", EXIT_FAILURE + 4)
    if not isinstance(settings["report_limit"], int) or settings["report_limit"] <= 0:
        raise TrackerError("config.settings.report_limit must be positive integer", EXIT_FAILURE + 4)
    if settings["default_owner"] not in sources:
        raise TrackerError("config.settings.default_owner must map to a source", EXIT_FAILURE + 4)


def validate_state(state: dict[str, Any], config: dict[str, Any]) -> None:
    if state.get("version") != 1:
        raise TrackerError("state.version must be 1", EXIT_FAILURE + 4)
    if not isinstance(state.get("updated_at"), str):
        raise TrackerError("state.updated_at must be a timestamp string", EXIT_FAILURE + 4)

    state_sources = ensure_dict(state.get("sources"), "state.sources")
    config_sources = ensure_dict(config.get("sources"), "config.sources")

    for source_name in config_sources:
        src = ensure_dict(state_sources.get(source_name), f"state.sources.{source_name}")
        for field in ("last_seen_sha", "last_seen_at", "last_scan_status"):
            if field not in src:
                raise TrackerError(f"state.sources.{source_name}.{field} is required", EXIT_FAILURE + 4)
        if not isinstance(src["last_seen_sha"], str) or not src["last_seen_sha"].strip():
            raise TrackerError(f"state.sources.{source_name}.last_seen_sha must be non-empty sha", EXIT_FAILURE + 4)


def classify_file(path: str, config: dict[str, Any]) -> tuple[str, str]:
    for rule in config.get("ownership_rules", []):
        if fnmatch.fnmatch(path, rule["pattern"]):
            return rule["owner"], rule["mode"]
    return config["settings"]["default_owner"], "track"


def normalize_commit(data: dict[str, Any]) -> dict[str, str]:
    return {
        "sha": data["sha"],
        "date": data["commit"]["committer"]["date"],
        "message": data["commit"]["message"].splitlines()[0],
    }


def truncate_items(items: list[Any], limit: int) -> list[Any]:
    if len(items) <= limit:
        return items
    return items[:limit]


def find_file_latest_sha(commit_file_map: dict[str, list[str]]) -> dict[str, str]:
    latest: dict[str, str] = {}
    for sha, files in commit_file_map.items():
        for path in files:
            if path not in latest:
                latest[path] = sha
    return latest


def collect_source_changes(
    name: str,
    source_cfg: dict[str, Any],
    baseline_sha: str,
    config: dict[str, Any],
    client: GitHubClient,
) -> SourceResult:
    max_commits = config["settings"]["max_commits"]
    repo = source_cfg["repo"]
    branch = source_cfg["branch"]

    head = client.get_head_commit(repo, branch)
    head_sha = head["sha"]
    warnings: list[str] = []

    if head_sha == baseline_sha:
        return SourceResult(
            name=name,
            repo=repo,
            branch=branch,
            baseline_sha=baseline_sha,
            head_sha=head_sha,
            head_date=head["date"],
            head_message=head["message"],
            new_commits=[],
            changed_files=[],
            tracked_files=[],
            escalated_files=[],
            conflict_files=[],
            warnings=[],
            scan_status="no_changes",
            file_latest_sha={},
            commit_file_map={},
        )

    new_commits: list[dict[str, str]] = []
    changed_files: set[str] = set()
    commit_file_map: dict[str, list[str]] = {}

    rewrite_fallback = False
    try:
        compare_data = client.compare(repo, baseline_sha, head_sha)
        compare_commits = compare_data.get("commits", [])
        for commit in compare_commits:
            new_commits.append(normalize_commit(commit))
        for changed in compare_data.get("files", []):
            changed_files.add(changed["filename"])

        if len(new_commits) > max_commits:
            new_commits = new_commits[-max_commits:]
            warnings.append(f"Truncated new commit list to max_commits={max_commits}")

        for commit in new_commits:
            detail = client.get_commit(repo, commit["sha"])
            files = [f["filename"] for f in detail.get("files", [])]
            commit_file_map[commit["sha"]] = files
            changed_files.update(files)

    except GitHubAPIError as exc:
        if exc.status_code not in {404, 409}:
            raise
        rewrite_fallback = True

    if rewrite_fallback:
        warnings.append(
            "Baseline is not directly comparable to current head (possible force-push/rewrite). "
            f"Falling back to latest {max_commits} commits."
        )
        commit_list = client.list_commits(repo, branch, max_commits)
        for raw_commit in commit_list:
            commit = normalize_commit(raw_commit)
            new_commits.append(commit)
            detail = client.get_commit(repo, commit["sha"])
            files = [f["filename"] for f in detail.get("files", [])]
            commit_file_map[commit["sha"]] = files
            changed_files.update(files)

    tracked_files: list[str] = []
    escalated_files: list[str] = []
    for path in sorted(changed_files):
        owner, mode = classify_file(path, config)
        if mode == "escalate":
            escalated_files.append(path)
            continue
        if owner != name:
            escalated_files.append(path)
            continue
        tracked_files.append(path)

    scan_status = "changed" if new_commits or changed_files else "no_changes"

    return SourceResult(
        name=name,
        repo=repo,
        branch=branch,
        baseline_sha=baseline_sha,
        head_sha=head_sha,
        head_date=head["date"],
        head_message=head["message"],
        new_commits=new_commits,
        changed_files=sorted(changed_files),
        tracked_files=tracked_files,
        escalated_files=sorted(set(escalated_files)),
        conflict_files=[],
        warnings=warnings,
        scan_status=scan_status,
        file_latest_sha=find_file_latest_sha(commit_file_map),
        commit_file_map=commit_file_map,
    )


def detect_conflicts(results: dict[str, SourceResult]) -> list[dict[str, Any]]:
    source_paths: dict[str, set[str]] = {name: set(result.changed_files) for name, result in results.items()}

    source_names = list(source_paths.keys())
    conflicts: list[dict[str, Any]] = []
    for i, name_a in enumerate(source_names):
        for name_b in source_names[i + 1 :]:
            overlap = sorted(source_paths[name_a] & source_paths[name_b])
            for path in overlap:
                conflicts.append({"path": path, "sources": [name_a, name_b]})

    conflict_paths = {entry["path"] for entry in conflicts}
    for result in results.values():
        result.conflict_files = sorted(path for path in result.changed_files if path in conflict_paths)
        result.tracked_files = sorted(path for path in result.tracked_files if path not in conflict_paths)

    return conflicts


def commit_is_low_risk(result: SourceResult, commit_sha: str, conflict_paths: set[str]) -> bool:
    files = result.commit_file_map.get(commit_sha, [])
    if not files:
        return False
    tracked = set(result.tracked_files)
    for path in files:
        if path in conflict_paths:
            return False
        if path not in tracked:
            return False
    return True


def safe_tmp_name(source_name: str, path: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9_.-]", "_", path)
    return f"/tmp/{source_name}-{cleaned}"


def build_suggestions_md(results: dict[str, SourceResult], conflicts: list[dict[str, Any]]) -> str:
    lines: list[str] = ["# Suggested Apply Commands", ""]
    conflict_paths = {entry["path"] for entry in conflicts}

    for source_name, result in results.items():
        lines.append(f"## {source_name}")
        lines.append("")
        lines.append(f"- Repo: `{result.repo}`")
        lines.append(f"- Branch: `{result.branch}`")
        lines.append(f"- Baseline: `{result.baseline_sha}`")
        lines.append(f"- Head: `{result.head_sha}`")
        lines.append("")
        lines.append("### Fetch")
        lines.append("")
        lines.append(f"```bash\ngit fetch https://github.com/{result.repo}.git {result.branch}\n```")
        lines.append("")

        low_risk = [
            commit
            for commit in result.new_commits
            if commit_is_low_risk(result, commit["sha"], conflict_paths)
        ]
        if low_risk:
            lines.append("### Low Risk (Owned-Only Commit Cherry-Picks)")
            lines.append("")
            lines.append("```bash")
            for commit in low_risk:
                lines.append(f"git cherry-pick -x {commit['sha']}")
            lines.append("```")
            lines.append("")

        medium_files = sorted(result.tracked_files)
        if medium_files:
            lines.append("### Medium Risk (File-Level Review + Apply)")
            lines.append("")
            for path in medium_files:
                sha = result.file_latest_sha.get(path, result.head_sha)
                tmp_path = safe_tmp_name(source_name, path)
                lines.append(f"#### `{path}`")
                lines.append("")
                lines.append("```bash")
                lines.append(f"git show {sha}:{path} > {tmp_path}")
                lines.append(f"git diff --no-index {path} {tmp_path}")
                lines.append("```")
                lines.append("")

        if result.conflict_files:
            lines.append("### Suppressed (Conflict)")
            lines.append("")
            for path in result.conflict_files:
                lines.append(f"- `{path}`")
            lines.append("")

        if result.escalated_files:
            lines.append("### Escalated (Cross-Owner / Explicit Escalate Rule)")
            lines.append("")
            for path in result.escalated_files:
                lines.append(f"- `{path}`")
            lines.append("")

        if not low_risk and not medium_files and not result.conflict_files and not result.escalated_files:
            lines.append("No suggestions for this source.")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def build_report_json(
    generated_at: str,
    results: dict[str, SourceResult],
    conflicts: list[dict[str, Any]],
    report_limit: int,
) -> dict[str, Any]:
    source_payload: dict[str, Any] = {}
    for source_name, result in results.items():
        source_payload[source_name] = {
            "repo": result.repo,
            "branch": result.branch,
            "baseline_sha": result.baseline_sha,
            "head": {
                "sha": result.head_sha,
                "date": result.head_date,
                "message": result.head_message,
            },
            "scan_status": result.scan_status,
            "warnings": result.warnings,
            "new_commits": truncate_items(result.new_commits, report_limit),
            "changed_files": truncate_items(result.changed_files, report_limit),
            "tracked_files": truncate_items(result.tracked_files, report_limit),
            "escalated_files": truncate_items(result.escalated_files, report_limit),
            "conflict_files": truncate_items(result.conflict_files, report_limit),
        }

    total_new_commits = sum(len(result.new_commits) for result in results.values())
    total_tracked_files = sum(len(result.tracked_files) for result in results.values())
    total_escalated_files = sum(len(result.escalated_files) for result in results.values())

    return {
        "version": 1,
        "generated_at": generated_at,
        "summary": {
            "changes_detected": total_new_commits > 0 or total_tracked_files > 0 or total_escalated_files > 0,
            "total_new_commits": total_new_commits,
            "total_tracked_files": total_tracked_files,
            "total_escalated_files": total_escalated_files,
            "total_conflicts": len(conflicts),
        },
        "sources": source_payload,
        "conflicts": truncate_items(conflicts, report_limit),
    }


def build_report_md(report_json: dict[str, Any]) -> str:
    lines: list[str] = ["# Upstream Tracking Report", ""]
    lines.append(f"Generated: `{report_json['generated_at']}`")
    lines.append("")

    lines.append("## Source Heads and Dates")
    lines.append("")
    for source_name, source in report_json["sources"].items():
        head = source["head"]
        lines.append(
            f"- `{source_name}`: `{head['sha']}` at `{head['date']}` ({head['message']})"
        )
    lines.append("")

    lines.append("## New Commits Per Source")
    lines.append("")
    for source_name, source in report_json["sources"].items():
        lines.append(f"### {source_name}")
        commits = source["new_commits"]
        if not commits:
            lines.append("- No new commits.")
        else:
            for commit in commits:
                lines.append(f"- `{commit['sha']}` `{commit['date']}` {commit['message']}")
        lines.append("")

    lines.append("## Owned Path Changes")
    lines.append("")
    for source_name, source in report_json["sources"].items():
        lines.append(f"### {source_name}")
        tracked = source["tracked_files"]
        escalated = source["escalated_files"]
        conflict_files = source["conflict_files"]
        if tracked:
            lines.append("Tracked:")
            for path in tracked:
                lines.append(f"- `{path}`")
        else:
            lines.append("Tracked: none")
        if escalated:
            lines.append("Escalated:")
            for path in escalated:
                lines.append(f"- `{path}`")
        else:
            lines.append("Escalated: none")
        if conflict_files:
            lines.append("Conflicts (suppressed from suggestions):")
            for path in conflict_files:
                lines.append(f"- `{path}`")
        lines.append("")

    lines.append("## Cross-Source Overlaps / Conflicts")
    lines.append("")
    conflicts = report_json.get("conflicts", [])
    if not conflicts:
        lines.append("No overlaps detected.")
    else:
        for conflict in conflicts:
            lines.append(
                f"- `{conflict['path']}` touched by `{', '.join(conflict['sources'])}`"
            )
    lines.append("")

    lines.append("## Suggested Apply Commands")
    lines.append("")
    lines.append("See `.upstream-tracker/reports/suggestions.md`.")
    lines.append("")

    summary = report_json["summary"]
    lines.append("## Summary")
    lines.append("")
    lines.append(f"- changes_detected: `{summary['changes_detected']}`")
    lines.append(f"- total_new_commits: `{summary['total_new_commits']}`")
    lines.append(f"- total_tracked_files: `{summary['total_tracked_files']}`")
    lines.append(f"- total_escalated_files: `{summary['total_escalated_files']}`")
    lines.append(f"- total_conflicts: `{summary['total_conflicts']}`")

    return "\n".join(lines).rstrip() + "\n"


def run_tracker(
    config_path: Path,
    state_path: Path,
    out_dir: Path,
    dry_run: bool = False,
    client: GitHubClient | None = None,
    generated_at: str | None = None,
) -> tuple[dict[str, Any], bool, dict[str, Any]]:
    config_raw = ensure_dict(load_structured_file(config_path), "config")
    validate_config(config_raw)

    state_raw = ensure_dict(load_structured_file(state_path), "state")
    validate_state(state_raw, config_raw)

    active_client = client or GitHubClient(token=os.getenv("GITHUB_TOKEN"))
    timestamp = generated_at or utc_now_iso()

    next_state = copy.deepcopy(state_raw)
    results: dict[str, SourceResult] = {}

    for source_name, source_cfg in config_raw["sources"].items():
        if not source_cfg.get("enabled", True):
            continue

        baseline_sha = state_raw["sources"][source_name]["last_seen_sha"]
        result = collect_source_changes(
            source_name,
            source_cfg,
            baseline_sha,
            config_raw,
            active_client,
        )
        results[source_name] = result

        next_state["sources"][source_name]["last_seen_sha"] = result.head_sha
        next_state["sources"][source_name]["last_seen_at"] = result.head_date
        next_state["sources"][source_name]["last_scan_status"] = result.scan_status

    conflicts = detect_conflicts(results)
    report_json = build_report_json(
        generated_at=timestamp,
        results=results,
        conflicts=conflicts,
        report_limit=config_raw["settings"]["report_limit"],
    )
    report_md = build_report_md(report_json)
    suggestions_md = build_suggestions_md(results, conflicts)

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "latest.json").write_text(json.dumps(report_json, indent=2, sort_keys=True) + "\n")
    (out_dir / "latest.md").write_text(report_md)
    (out_dir / "suggestions.md").write_text(suggestions_md)

    if not dry_run:
        next_state["updated_at"] = timestamp
        state_path.write_text(json.dumps(next_state, indent=2, sort_keys=True) + "\n")

    changes_detected = report_json["summary"]["changes_detected"]
    return report_json, changes_detected, next_state


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Track upstream changes and generate reports.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser("run", help="Run tracker")
    run_parser.add_argument("--config", required=True, type=Path)
    run_parser.add_argument("--state", required=True, type=Path)
    run_parser.add_argument("--out-dir", required=True, type=Path)
    run_parser.add_argument("--dry-run", action="store_true", help="Do not update state")

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    if args.command != "run":
        raise TrackerError(f"Unsupported command {args.command}")

    try:
        _, changes_detected, _ = run_tracker(
            config_path=args.config,
            state_path=args.state,
            out_dir=args.out_dir,
            dry_run=args.dry_run,
        )
    except TrackerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return exc.code
    except Exception as exc:  # pragma: no cover
        print(f"error: unexpected failure: {exc}", file=sys.stderr)
        return EXIT_FAILURE + 9

    return EXIT_CHANGES if changes_detected else EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
