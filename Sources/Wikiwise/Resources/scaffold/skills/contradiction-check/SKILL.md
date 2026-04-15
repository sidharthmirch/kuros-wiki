---
name: contradiction-check
description: Detect contradictory or stale claims across notes, sources, briefs, and threads.
---

# Contradiction Check

## Purpose

Find claims that conflict, lack sources, or may be stale relative to newer material.

## Inputs

- A claim, thread, brief, source, or whole workspace scan.

## Outputs

- A reviewable report in `drafts/` or `claims/`.
- Suggested claim updates with citations.
- No silent rewrites of authored notes.

## Invocation Expectations

1. Gather claims from `claims/`, `notes/`, `threads/`, and `briefs/`.
2. Compare them against source summaries and newer dated material.
3. Classify findings as contradiction, stale claim, missing citation, or unresolved tension.
4. Write a report with exact file references and suggested review actions.

## Rules

- Do not resolve contradictions by deleting one side.
- Prefer "tension" when evidence is incomplete.
- Require citations for any proposed replacement claim.
