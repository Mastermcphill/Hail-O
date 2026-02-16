# GitHub Actions Nightly Release Gate

This repository runs the release gate nightly via GitHub Actions using:
- Workflow: `.github/workflows/nightly_release_gate.yml`
- Schedule: daily at `02:00 UTC`
- Manual trigger: `workflow_dispatch`

## Required Secret

Add this repository secret:
- Name: `HAILO_STAGING_DATABASE_URL`
- Value: staging external Postgres connection URL

GitHub UI path:
1. Open repository `Settings`.
2. Go to `Secrets and variables` -> `Actions`.
3. Click `New repository secret`.
4. Add `HAILO_STAGING_DATABASE_URL`.

## Manual Run

1. Open repository `Actions`.
2. Select workflow `Nightly Release Gate`.
3. Click `Run workflow`.
4. Select branch and confirm run.

## Artifacts

After each run, artifacts are uploaded in the run page under `Artifacts`:
- Name: `release-gate-artifacts`
- Contents: `test_artifacts/ops/**`
