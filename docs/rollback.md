# Rollback Runbook

## Immediate rollback
1. Open Render service `hail-o-api`.
2. Select the previous known-good deploy.
3. Redeploy that version.
4. Keep `hail-o-api-staging` running on the current candidate commit for diagnosis.

## Post-rollback checks
1. Verify `/health` returns `ok: true`.
2. Validate one authenticated read endpoint.
3. Confirm no migration drift (same `migration_head` expected).
4. Capture an incident snapshot:
   - `powershell -ExecutionPolicy Bypass -File tool/incident_snapshot.ps1`

## Data safety notes
- Migrations are idempotent and schema-tracked.
- Rollback should not include destructive schema changes without a dedicated downgrade script.
- Keep staged migrations additive to reduce rollback risk.

## Schema version verification
- Compare `/health` response `build.migration_head` before and after rollback.
- For staging/prod schema separation, also verify `build.db_schema` matches expected:
  - staging: `hailo_staging`
  - production: `hailo_prod`
