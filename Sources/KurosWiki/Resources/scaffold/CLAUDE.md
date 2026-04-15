# {{WIKI_NAME}} — ambient research schema

This is a local-first ambient research workspace. It keeps the original Kuro's Wiki markdown/wiki strengths, but the primary model is now note-first research: captures, notes, sources, threads, briefs, sessions, tasks, entities, claims, questions, and drafts.

## Product Shape

Kuro's Wiki is the workbench. The AI provider is swappable.

- The app owns the workspace model, file layout, ambient jobs, and provenance.
- The provider supplies reasoning and execution through terminal workflows.
- Skills define stable workflows independent of provider.
- Generated artifacts are reviewable unless explicitly accepted.

## Layout

- `inbox/` — rough captures, URLs, excerpts, and unprocessed thoughts.
- `notes/` — authored notes and structured observations.
- `sources/` — source records and source summaries.
- `threads/` — research threads connecting notes, claims, questions, and sources.
- `briefs/` — synthesized research artifacts.
- `sessions/` — closeouts, recaps, and daily reviews.
- `tasks/` — research tasks and follow-ups.
- `entities/` — entities worth tracking.
- `claims/` — atomic source-backed claims.
- `questions/` — open questions.
- `drafts/` — AI-generated proposals with review status.
- `wiki/` — compatibility pages for the original compiled wiki view.
- `raw/` — immutable source material.
- `site/` — compiler assets and generated HTML.
- `skills/` — canonical skills.
- `.claude/skills/` — Claude Code bridge.
- `.kuros-wiki/` — app-owned provider state and ambient job records.
- `.claude/active-user` — active workspace profile.

## Profiles

Profiles are local to this workspace. New workspaces start as `kuro`, and users can add valid profiles such as `sidharth` and `vidur` in Kuro's Wiki settings.

- Read `.claude/active-user` before attributing edits.
- Allowed profiles are stored in `.kuros-wiki/workspace.json`.
- Profile IDs use lowercase letters, numbers, hyphens, and underscores, start with a letter or number, and are at most 32 characters.
- Use `created_by`, `updated_by`, or `authors` in frontmatter when authorship matters.

## Frontmatter

Every generated artifact should include:

```yaml
title:
type: note
status: active
provider: codex
skill: distill-note
action_level: suggest
created_by: kuro
updated_by: kuro
authors:
  - kuro
created_at:
updated_at:
accepted: false
```

Use `accepted: true` only for authored notes or user-approved outputs.

## Writing Style

- TL;DR first for notes and briefs.
- Direct, plain, evidence-aware.
- Shorter is better when links carry the graph.
- Use `[[wikilinks]]` for local relationships.
- Cite sources for claims.
- Mark uncertainty clearly.

## Ambient Modes

The ambient layer can:

- Suggest: links, tags, entities, threads, questions, next actions.
- Draft: summaries, briefs, closeouts, structured notes.
- Maintain: indexes, backlinks, digests, stale-claim reports.

Do not perform destructive edits silently. Draft first.

## Provider Switching

Do not encode provider-specific assumptions into notes. Provider-specific commands and bridges belong in `.kuros-wiki/provider-bridge.md`, `.kuros-wiki/workspace.json`, and adapter-specific folders such as `.claude/skills/`.

Artifacts should always say which provider and skill produced them.

## Live Viewer

Kuro's Wiki watches the project directory and rebuilds markdown output. If auto-refresh misses changes:

```sh
touch .rebuild
```

The active profile is available at `.claude/active-user`. The active file path is available at `.claude/active-file`.
