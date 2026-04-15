---
name: distill-note
description: Turn rough captures or messy notes into structured local research notes while preserving the authored original.
---

# Distill Note

## Purpose

Convert rough material into a clearer note, claim, question, entity, or thread without silently rewriting the user's authored text.

## Inputs

- One or more files from `inbox/` or `notes/`.
- Optional related sources, thread, or current research question.

## Outputs

- A reviewable draft in `drafts/`, or a new structured note in `notes/` when explicitly requested.
- Suggested links, tags, entities, claims, and questions.

## Invocation Expectations

1. Read the target file and nearby context from `index.md`, `threads/`, and related wikilinks.
2. Extract the durable idea, open question, evidence, and next action.
3. Write a reviewable draft unless the user explicitly asks for a direct authored-note edit.
4. Preserve provenance: provider, skill, source path, action level, and accepted status.

## Output Sections

- TL;DR
- Context
- Durable note
- Claims
- Questions
- Related links
- Next action

## Rules

- Do not delete the original capture.
- Prefer short notes with strong links over long summary dumps.
- Use `[[wikilinks]]` for workspace-native connections.
