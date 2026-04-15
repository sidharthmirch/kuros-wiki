#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKILLS = [
    "capture-source",
    "distill-note",
    "connect-thread",
    "build-brief",
    "session-closeout",
    "contradiction-check",
    "daily-review",
    "research-sprint",
]


def assert_true(condition, message):
    if not condition:
        raise AssertionError(message)


def test_skill_scaffold():
    skills_root = ROOT / "Sources/KurosWiki/Resources/scaffold/skills"
    for skill in SKILLS:
        path = skills_root / skill / "SKILL.md"
        text = path.read_text()
        assert_true(text.startswith("---\n"), f"{skill} is missing frontmatter")
        assert_true(f"name: {skill}" in text, f"{skill} has wrong name")
        assert_true("## Purpose" in text, f"{skill} is missing purpose")
        assert_true("## Inputs" in text, f"{skill} is missing inputs")
        assert_true("## Outputs" in text, f"{skill} is missing outputs")
        assert_true("## Invocation Expectations" in text, f"{skill} is missing invocation expectations")


def test_workspace_state_template_is_valid_json():
    scaffold = (ROOT / "Sources/KurosWiki/WikiScaffold.swift").read_text()
    start = scaffold.index('let workspaceState = """') + len('let workspaceState = """')
    end = scaffold.index('"""', start)
    state = json.loads(scaffold[start:end])
    assert_true(state["schemaVersion"] == 1, "workspace schema version should be 1")
    assert_true(state["settings"]["activeProvider"] == "codex", "default provider should be codex")
    assert_true(state["settings"]["defaultActionLevel"] == "suggest", "default action level should be suggest")


def test_graph_knows_research_types():
    build_js = (ROOT / "Sources/KurosWiki/Resources/build.js").read_text()
    for label in ["Inbox", "Note", "Thread", "Brief", "Session", "Task", "Entity", "Claim", "Question", "Draft"]:
        assert_true(label in build_js, f"build.js is missing graph label {label}")


def test_site_build_excludes_agent_skills():
    build_js = (ROOT / "Sources/KurosWiki/Resources/build.js").read_text()
    assert_true("dir === rootDir && entry === 'skills'" in build_js, "site build should exclude only top-level skills/")


def main():
    test_skill_scaffold()
    test_workspace_state_template_is_valid_json()
    test_graph_knows_research_types()
    test_site_build_excludes_agent_skills()
    print("smoke tests passed")


if __name__ == "__main__":
    main()
