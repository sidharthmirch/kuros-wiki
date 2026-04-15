# Agent Instructions

This is a local-first ambient research workspace. Kuro's Wiki owns the markdown workspace model; the active AI provider supplies reasoning and execution through the terminal.

Read `CLAUDE.md` for the full schema when available. This file exists so Codex, Claude Code, Cursor-compatible agents, and other tools can work from the same rules.

## Layout

- `inbox/` — quick captures, rough thoughts, URLs, and excerpts.
- `notes/` — authored notes and durable observations.
- `sources/` — captured source records and source summaries.
- `threads/` — evolving research threads connecting notes, claims, questions, and sources.
- `briefs/` — synthesized research artifacts.
- `sessions/` — session closeouts and daily reviews.
- `tasks/` — research tasks and follow-ups.
- `entities/` — people, organizations, projects, places, and other entities.
- `claims/` — atomic source-backed claims.
- `questions/` — open research questions.
- `drafts/` — reviewable AI drafts and suggestions.
- `wiki/` — compatibility pages for the original Kuro's Wiki viewer.
- `raw/` — immutable raw source material.
- `site/` — build tooling and compiled output.
- `.kuros-wiki/` — app-owned settings, provider bridge, and ambient job state.
- `skills/` — canonical skill instructions.
- `.claude/skills/` — Claude Code bridge copied from canonical skills.

## Provider Model

The workspace must remain provider-agnostic.

- App-owned model: notes, sources, threads, briefs, sessions, tasks, entities, claims, questions, drafts, jobs, provenance.
- Provider-owned execution: reasoning, source distillation, synthesis, and edits requested through terminal workflows.
- Canonical skills: `skills/<skill-name>/SKILL.md`.
- Claude bridge: `.claude/skills/<skill-name>/SKILL.md`.
- Provider state: `.kuros-wiki/workspace.json`.
- Active profile: `.claude/active-user`.

## Profiles

Profiles are workspace-scoped. The default profile is `kuro`; users can add valid local profiles such as `sidharth` and `vidur` in Kuro's Wiki settings.

- Read `.claude/active-user` before making attributed edits.
- Check `profiles` in `.kuros-wiki/workspace.json` if you need to verify the active profile is allowed.
- Attribute authored or edited artifacts with `created_by`, `updated_by`, or `authors` when appropriate.

When creating generated artifacts, include frontmatter:

```yaml
provider: codex
skill: distill-note
action_level: suggest
updated_by: kuro
authors:
  - kuro
created_at: 2026-04-13T12:00:00Z
accepted: false
```

## Core Rules

- Do not silently overwrite authored notes.
- Put proposed outputs in `drafts/`, `briefs/`, or `sessions/` with `accepted: false` unless the user approves direct edits.
- Preserve provenance: provider, skill, date, source path, and action level.
- Use `[[wikilinks]]` to connect workspace items.
- Cite sources when making claims.
- Keep raw source material immutable.
- Prefer small durable notes and explicit links over long summary dumps.

## Skills

Read the relevant skill file before running a workflow.

| Skill | Purpose |
| --- | --- |
| `capture-source` | Capture URL, pasted text, excerpts, or documents with provenance |
| `distill-note` | Turn rough notes into structured reviewable notes |
| `connect-thread` | Link notes, sources, entities, claims, and questions into threads |
| `build-brief` | Generate a reviewable brief from a thread |
| `session-closeout` | Summarize a work session and next actions |
| `contradiction-check` | Detect conflicting or stale claims |
| `daily-review` | Produce a daily digest |
| `research-sprint` | Run a focused research pass |
| `whoami` | Report the active workspace profile |

## Live Viewer

Kuro's Wiki watches this folder. Markdown and CSS changes trigger rebuilds. If the viewer misses a bulk update, touch `.rebuild`:

```sh
touch .rebuild
```

The current active profile is written to `.claude/active-user`, and the current active file is written to `.claude/active-file` for compatible agents.
