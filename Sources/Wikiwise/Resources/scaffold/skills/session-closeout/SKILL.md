---
name: session-closeout
description: Close a research session with a summary, changed files, open loops, and recommended next actions.
---

# Session Closeout

## Purpose

Turn a work session into a durable handoff so research can resume later without rediscovery.

## Inputs

- Recent changed files, active note, active thread, or user prompt.

## Outputs

- A dated markdown closeout in `sessions/`.
- Next actions in `tasks/` when appropriate.
- Suggested follow-up skills.

## Invocation Expectations

1. Inspect recent changes and the active file when available.
2. Summarize what changed, why it matters, and what remains open.
3. Create a closeout artifact; do not rewrite authored notes.
4. Include provider and skill provenance.

## Closeout Shape

- What changed
- Decisions made
- Open loops
- Next actions
- Files touched
- Suggested next skill

## Rules

- Keep the closeout concise.
- Mark uncertainty clearly.
