# Nightly Staging Release Gate (hail-o-ci)

The `hail-o-ci` worker runs a PowerShell scheduler (`tool/ci_nightly_scheduler.ps1`) that executes the staging release gate daily at **02:00 UTC**.

## Required Worker Environment Variables

- `HAILO_STAGING_DATABASE_URL` (required): external staging Postgres connection string used by migration head parity.

## What to Look for in Render Logs

Each nightly run prints:

- `NIGHTLY_GATE_START <iso_timestamp>`
- `NIGHTLY_GATE_ARTIFACT_DIR <path>`
- `NIGHTLY_GATE_RESULT PASS|FAIL`

Scheduler logs also print:

- `NIGHTLY_SCHEDULER_SLEEP_UNTIL <iso_timestamp> (<seconds>s)`
- `NIGHTLY_SCHEDULER_RUN_START <iso_timestamp>`
- `NIGHTLY_SCHEDULER_RUN_EXIT <code>`

## Artifact Location

Artifacts are written under:

- `test_artifacts/ops/<yyyyMMdd_HHmmss>/`
