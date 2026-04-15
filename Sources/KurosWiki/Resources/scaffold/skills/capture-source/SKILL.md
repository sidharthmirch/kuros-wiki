---
name: capture-source
description: Capture a URL, pasted excerpt, document, or rough source note into the local research workspace with durable provenance.
---

# Capture Source

## Purpose

Turn source material into a local-first source record without losing origin, context, or review status.

## Inputs

- URL, pasted text, file path, excerpt, highlight, or citation.
- Optional thread, note, claim, or question the source belongs to.

## Outputs

- A markdown file in `sources/` with frontmatter.
- Optional raw material in `raw/` when the original content is long or immutable.
- Suggestions for related notes, entities, claims, questions, and threads.

## Invocation Expectations

1. Read `AGENTS.md` and `.kuros-wiki/provider-bridge.md`.
2. Preserve the original URL, author, title, access date, and capture context when available.
3. Create or update a `sources/<slug>.md` file. Do not overwrite authored notes.
4. Link the source to relevant notes, claims, questions, entities, and threads using `[[wikilinks]]`.
5. Record provenance in frontmatter: `provider`, `skill`, `created_at`, `action_level`, `accepted`.

## Output Shape

```markdown
---
title: "Source title"
type: source
url: https://example.com
author:
captured_at: 2026-04-13T12:00:00Z
provider: codex
skill: capture-source
action_level: suggest
accepted: false
---

# Source title

## Why it matters

## Key claims

## Links
```

## Rules

- Never fabricate metadata.
- Keep long verbatim excerpts in `raw/` or quote sparingly.
- If unsure how to classify the material, leave it in `inbox/` and propose next steps.
