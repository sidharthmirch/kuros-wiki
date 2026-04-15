# Upstream Tracking

Kuro's Wiki includes a daily automation pipeline that tracks changes from:

- `TristanH/wikiwise` (`main`)
- `saivishnu2299/ambient-wikiwise` (`main`)

It updates one rolling PR (`chore: upstream tracking report`) with tracker artifacts only.

## What It Produces

The tracker writes only files under `.upstream-tracker/`:

- `.upstream-tracker/reports/latest.md`
- `.upstream-tracker/reports/latest.json`
- `.upstream-tracker/reports/suggestions.md`
- `.upstream-tracker/state.json`

No app source files are modified by automation.

## Local Run

```bash
python3 scripts/upstream_tracker.py run \
  --config .upstream-tracker/config.yml \
  --state .upstream-tracker/state.json \
  --out-dir .upstream-tracker/reports
```

Dry run (report only, state unchanged):

```bash
python3 scripts/upstream_tracker.py run \
  --config .upstream-tracker/config.yml \
  --state .upstream-tracker/state.json \
  --out-dir .upstream-tracker/reports \
  --dry-run
```

Exit codes:

- `0` success, no changes detected
- `2` success, changes detected
- `>=10` hard failure (API/schema/runtime)

## Ownership And Conflict Policy

- `default_owner: wikiwise`
- curated ambient-owned paths are in `.upstream-tracker/config.yml`
- first matching ownership rule wins
- if both sources touch the same path since baseline, tracker marks `CONFLICT`
- conflicted paths are excluded from auto-apply suggestions

## Suggestions

Suggestions are command-only guidance, grouped by source and risk level:

- fetch commands
- low-risk commit cherry-picks when commit touches only owned, non-conflicting paths
- file-level `git show` + `git diff --no-index` review commands

## Workflow

Workflow: `.github/workflows/upstream-tracker.yml`

Triggers:

- daily cron
- manual dispatch (`force_pr`, `dry_run`)

When changes exist, it updates branch `automation/upstream-tracker` and creates/updates one PR into `main`.

## Tuning

Tune ownership map and settings in `.upstream-tracker/config.yml`:

- `ownership_rules`
- `settings.max_commits`
- `settings.report_limit`

Use the first week of reports to reduce false conflicts and escalations.
