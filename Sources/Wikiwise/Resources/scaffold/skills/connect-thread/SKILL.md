---
name: connect-thread
description: Link notes, sources, entities, claims, and questions into coherent research threads.
---

# Connect Thread

## Purpose

Maintain the research graph by turning scattered material into navigable threads.

## Inputs

- A note, source, claim, question, or existing thread.
- Optional target thread name.

## Outputs

- A new or updated file in `threads/`.
- Suggested backlinks from related notes, sources, entities, claims, and questions.
- A concise thread state: thesis, evidence, open questions, next sources.

## Invocation Expectations

1. Read the target item and search nearby folders for related material.
2. Identify whether this belongs in an existing thread or needs a new one.
3. Write changes as suggestions or drafts unless the user approves direct edits.
4. Record provenance in every generated artifact.

## Thread Shape

```markdown
---
title: "Thread title"
type: thread
status: active
provider:
skill: connect-thread
---

# Thread title

## Current thesis
## Evidence
## Counterpoints
## Open questions
## Next sources
```

## Rules

- No orphan threads. Link out to relevant workspace items.
- Prefer explicit uncertainty over premature synthesis.
