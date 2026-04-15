#!/usr/bin/env python3

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from upstream_tracker import GitHubAPIError, TrackerError, run_tracker


def raw_commit(sha: str, date: str, message: str) -> dict:
    return {
        "sha": sha,
        "commit": {
            "committer": {"date": date},
            "message": message,
        },
    }


def commit_detail(sha: str, date: str, message: str, files: list[str]) -> dict:
    data = raw_commit(sha, date, message)
    data["files"] = [{"filename": f} for f in files]
    return data


class FakeGitHubClient:
    def __init__(self, heads=None, compares=None, commit_details=None, commit_lists=None):
        self.heads = heads or {}
        self.compares = compares or {}
        self.commit_details = commit_details or {}
        self.commit_lists = commit_lists or {}

    def get_head_commit(self, repo: str, branch: str) -> dict:
        return self.heads[(repo, branch)]

    def compare(self, repo: str, base: str, head: str) -> dict:
        value = self.compares[(repo, base, head)]
        if isinstance(value, Exception):
            raise value
        return value

    def get_commit(self, repo: str, sha: str) -> dict:
        return self.commit_details[(repo, sha)]

    def list_commits(self, repo: str, branch: str, per_page: int) -> list[dict]:
        return self.commit_lists[(repo, branch)][:per_page]


class UpstreamTrackerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.config = self.root / "config.yml"
        self.state = self.root / "state.json"
        self.out = self.root / "reports"

    def tearDown(self):
        self.tmp.cleanup()

    def write_config(self):
        config = {
            "version": 1,
            "sources": {
                "wikiwise": {
                    "repo": "TristanH/wikiwise",
                    "branch": "main",
                    "enabled": True,
                },
                "ambient": {
                    "repo": "saivishnu2299/ambient-wikiwise",
                    "branch": "main",
                    "enabled": True,
                },
            },
            "ownership_rules": [
                {
                    "pattern": "Sources/KurosWiki/Ambient*.swift",
                    "owner": "ambient",
                    "mode": "track",
                }
            ],
            "settings": {
                "max_commits": 20,
                "report_limit": 200,
                "default_owner": "wikiwise",
            },
        }
        self.config.write_text(json.dumps(config, indent=2))

    def write_state(self, wiki_sha="w0", ambient_sha="a0"):
        state = {
            "version": 1,
            "updated_at": "2026-04-14T00:00:00Z",
            "sources": {
                "wikiwise": {
                    "last_seen_sha": wiki_sha,
                    "last_seen_at": "2026-04-14T00:00:00Z",
                    "last_scan_status": "initialized",
                },
                "ambient": {
                    "last_seen_sha": ambient_sha,
                    "last_seen_at": "2026-04-14T00:00:00Z",
                    "last_scan_status": "initialized",
                },
            },
        }
        self.state.write_text(json.dumps(state, indent=2))

    def load_latest(self) -> dict:
        return json.loads((self.out / "latest.json").read_text())

    def test_no_changes(self):
        self.write_config()
        self.write_state()
        client = FakeGitHubClient(
            heads={
                ("TristanH/wikiwise", "main"): {
                    "sha": "w0",
                    "date": "2026-04-14T00:00:00Z",
                    "message": "same",
                },
                ("saivishnu2299/ambient-wikiwise", "main"): {
                    "sha": "a0",
                    "date": "2026-04-14T00:00:00Z",
                    "message": "same",
                },
            }
        )

        report, changed, _ = run_tracker(self.config, self.state, self.out, client=client)

        self.assertFalse(changed)
        self.assertFalse(report["summary"]["changes_detected"])
        self.assertEqual(report["summary"]["total_new_commits"], 0)

    def test_wikiwise_only_change_generates_suggestions(self):
        self.write_config()
        self.write_state()
        commit = raw_commit("w1", "2026-04-15T00:00:00Z", "wiki change")
        client = FakeGitHubClient(
            heads={
                ("TristanH/wikiwise", "main"): {
                    "sha": "w1",
                    "date": "2026-04-15T00:00:00Z",
                    "message": "wiki change",
                },
                ("saivishnu2299/ambient-wikiwise", "main"): {
                    "sha": "a0",
                    "date": "2026-04-14T00:00:00Z",
                    "message": "same",
                },
            },
            compares={
                ("TristanH/wikiwise", "w0", "w1"): {
                    "commits": [commit],
                    "files": [{"filename": "Sources/KurosWiki/ContentView.swift"}],
                }
            },
            commit_details={
                ("TristanH/wikiwise", "w1"): commit_detail(
                    "w1",
                    "2026-04-15T00:00:00Z",
                    "wiki change",
                    ["Sources/KurosWiki/ContentView.swift"],
                )
            },
        )

        report, changed, _ = run_tracker(self.config, self.state, self.out, client=client)

        self.assertTrue(changed)
        tracked = report["sources"]["wikiwise"]["tracked_files"]
        self.assertIn("Sources/KurosWiki/ContentView.swift", tracked)
        suggestions = (self.out / "suggestions.md").read_text()
        self.assertIn("git show w1:Sources/KurosWiki/ContentView.swift", suggestions)

    def test_ambient_only_change_on_owned_path(self):
        self.write_config()
        self.write_state()
        commit = raw_commit("a1", "2026-04-15T00:00:00Z", "ambient change")
        client = FakeGitHubClient(
            heads={
                ("TristanH/wikiwise", "main"): {
                    "sha": "w0",
                    "date": "2026-04-14T00:00:00Z",
                    "message": "same",
                },
                ("saivishnu2299/ambient-wikiwise", "main"): {
                    "sha": "a1",
                    "date": "2026-04-15T00:00:00Z",
                    "message": "ambient change",
                },
            },
            compares={
                ("saivishnu2299/ambient-wikiwise", "a0", "a1"): {
                    "commits": [commit],
                    "files": [{"filename": "Sources/KurosWiki/AmbientViews.swift"}],
                }
            },
            commit_details={
                ("saivishnu2299/ambient-wikiwise", "a1"): commit_detail(
                    "a1",
                    "2026-04-15T00:00:00Z",
                    "ambient change",
                    ["Sources/KurosWiki/AmbientViews.swift"],
                )
            },
        )

        report, changed, _ = run_tracker(self.config, self.state, self.out, client=client)

        self.assertTrue(changed)
        tracked = report["sources"]["ambient"]["tracked_files"]
        self.assertIn("Sources/KurosWiki/AmbientViews.swift", tracked)

    def test_overlap_conflict_suppresses_patch_commands(self):
        self.write_config()
        self.write_state()
        wiki_commit = raw_commit("w1", "2026-04-15T00:00:00Z", "wiki")
        ambient_commit = raw_commit("a1", "2026-04-15T00:00:00Z", "ambient")
        shared_path = "Sources/KurosWiki/ContentView.swift"
        client = FakeGitHubClient(
            heads={
                ("TristanH/wikiwise", "main"): {
                    "sha": "w1",
                    "date": "2026-04-15T00:00:00Z",
                    "message": "wiki",
                },
                ("saivishnu2299/ambient-wikiwise", "main"): {
                    "sha": "a1",
                    "date": "2026-04-15T00:00:00Z",
                    "message": "ambient",
                },
            },
            compares={
                ("TristanH/wikiwise", "w0", "w1"): {
                    "commits": [wiki_commit],
                    "files": [{"filename": shared_path}],
                },
                ("saivishnu2299/ambient-wikiwise", "a0", "a1"): {
                    "commits": [ambient_commit],
                    "files": [{"filename": shared_path}],
                },
            },
            commit_details={
                ("TristanH/wikiwise", "w1"): commit_detail(
                    "w1",
                    "2026-04-15T00:00:00Z",
                    "wiki",
                    [shared_path],
                ),
                ("saivishnu2299/ambient-wikiwise", "a1"): commit_detail(
                    "a1",
                    "2026-04-15T00:00:00Z",
                    "ambient",
                    [shared_path],
                ),
            },
        )

        report, changed, _ = run_tracker(self.config, self.state, self.out, client=client)

        self.assertTrue(changed)
        self.assertEqual(report["summary"]["total_conflicts"], 1)
        suggestions = (self.out / "suggestions.md").read_text()
        self.assertIn("Suppressed (Conflict)", suggestions)
        self.assertNotIn(f"git show w1:{shared_path}", suggestions)
        self.assertNotIn(f"git show a1:{shared_path}", suggestions)

    def test_cross_owner_change_gets_escalated(self):
        self.write_config()
        self.write_state()
        commit = raw_commit("a1", "2026-04-15T00:00:00Z", "ambient touching wiki file")
        path = "Sources/KurosWiki/ContentView.swift"
        client = FakeGitHubClient(
            heads={
                ("TristanH/wikiwise", "main"): {
                    "sha": "w0",
                    "date": "2026-04-14T00:00:00Z",
                    "message": "same",
                },
                ("saivishnu2299/ambient-wikiwise", "main"): {
                    "sha": "a1",
                    "date": "2026-04-15T00:00:00Z",
                    "message": "ambient touching wiki file",
                },
            },
            compares={
                ("saivishnu2299/ambient-wikiwise", "a0", "a1"): {
                    "commits": [commit],
                    "files": [{"filename": path}],
                }
            },
            commit_details={
                ("saivishnu2299/ambient-wikiwise", "a1"): commit_detail(
                    "a1",
                    "2026-04-15T00:00:00Z",
                    "ambient touching wiki file",
                    [path],
                )
            },
        )

        report, changed, _ = run_tracker(self.config, self.state, self.out, client=client)

        self.assertTrue(changed)
        self.assertIn(path, report["sources"]["ambient"]["escalated_files"])
        self.assertNotIn(path, report["sources"]["ambient"]["tracked_files"])

    def test_rate_limit_or_5xx_keeps_state_unchanged(self):
        self.write_config()
        self.write_state()
        client = FakeGitHubClient(
            heads={
                ("TristanH/wikiwise", "main"): {
                    "sha": "w1",
                    "date": "2026-04-15T00:00:00Z",
                    "message": "changed",
                },
                ("saivishnu2299/ambient-wikiwise", "main"): {
                    "sha": "a0",
                    "date": "2026-04-14T00:00:00Z",
                    "message": "same",
                },
            },
            compares={
                ("TristanH/wikiwise", "w0", "w1"): GitHubAPIError(
                    "rate limited", 503, "server error"
                )
            },
        )

        before = self.state.read_text()
        with self.assertRaises(GitHubAPIError):
            run_tracker(self.config, self.state, self.out, client=client)
        after = self.state.read_text()
        self.assertEqual(before, after)

    def test_invalid_config_fails_fast(self):
        self.config.write_text("{}")
        self.write_state()
        client = FakeGitHubClient()

        with self.assertRaises(TrackerError):
            run_tracker(self.config, self.state, self.out, client=client)

    def test_force_push_rewrite_fallback(self):
        self.write_config()
        self.write_state()
        commit = raw_commit("w1", "2026-04-15T00:00:00Z", "rewrite commit")
        path = "Sources/KurosWiki/ContentView.swift"
        client = FakeGitHubClient(
            heads={
                ("TristanH/wikiwise", "main"): {
                    "sha": "w1",
                    "date": "2026-04-15T00:00:00Z",
                    "message": "rewrite commit",
                },
                ("saivishnu2299/ambient-wikiwise", "main"): {
                    "sha": "a0",
                    "date": "2026-04-14T00:00:00Z",
                    "message": "same",
                },
            },
            compares={
                ("TristanH/wikiwise", "w0", "w1"): GitHubAPIError(
                    "compare failed", 404, "not found"
                )
            },
            commit_lists={
                ("TristanH/wikiwise", "main"): [commit],
            },
            commit_details={
                ("TristanH/wikiwise", "w1"): commit_detail(
                    "w1",
                    "2026-04-15T00:00:00Z",
                    "rewrite commit",
                    [path],
                )
            },
        )

        report, changed, _ = run_tracker(self.config, self.state, self.out, client=client)

        self.assertTrue(changed)
        self.assertTrue(report["sources"]["wikiwise"]["warnings"])
        self.assertIn("force-push/rewrite", report["sources"]["wikiwise"]["warnings"][0])


if __name__ == "__main__":
    unittest.main()
