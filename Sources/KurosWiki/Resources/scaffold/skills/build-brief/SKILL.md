---
name: build-brief
description: Generate a reviewable research brief from one thread or a focused set of notes and sources.
---

# Build Brief

## Purpose

Create an evolving research artifact that synthesizes a thread without mutating the underlying notes.

## Inputs

- One thread or a focused set of notes, sources, claims, and questions.
- Optional audience, decision, or output length.

## Outputs

- A markdown draft in `briefs/` or `drafts/`.
- Explicit provenance and source links.
- Open questions and next-source recommendations.

## Invocation Expectations

1. Read the thread first, then linked notes and source summaries.
2. Separate evidence, interpretation, uncertainty, and recommendations.
3. Cite sources with `[[wikilinks]]`.
4. Write a draft with `accepted: false` unless the user asks to accept it.

## Brief Shape

- Executive summary
- Current thesis
- Evidence table
- Counterarguments
- Open questions
- Next steps
- Provenance

## Rules

- Never hide weak evidence.
- Do not overwrite a previous brief; create a new dated draft or update only with explicit approval.
