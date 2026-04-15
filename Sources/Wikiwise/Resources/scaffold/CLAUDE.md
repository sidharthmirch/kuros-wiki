# {{WIKI_NAME}} — ambient research schema

This is a local-first ambient research workspace. It keeps the original Wikiwise markdown/wiki strengths, but the primary model is now note-first research: captures, notes, sources, threads, briefs, sessions, tasks, entities, claims, questions, and drafts.

## Product Shape

Wikiwise is the workbench. The AI provider is swappable.

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
- `.wikiwise/` — app-owned provider state and ambient job records.

## Frontmatter

Every generated artifact should include:

```yaml
title:
type: note
status: active
provider: codex
skill: distill-note
action_level: suggest
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

Do not encode provider-specific assumptions into notes. Provider-specific commands and bridges belong in `.wikiwise/provider-bridge.md`, `.wikiwise/workspace.json`, and adapter-specific folders such as `.claude/skills/`.

Artifacts should always say which provider and skill produced them.

## Live Viewer

Wikiwise watches the project directory and rebuilds markdown output. If auto-refresh misses changes:

```sh
touch .rebuild
```

The active file path is available at `.claude/active-file`.
