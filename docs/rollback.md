# Rollback Runbook

## Immediate rollback
1. Open Render service `hail-o-api`.
2. Select the previous known-good deploy.
3. Redeploy that version.

## Post-rollback checks
1. Verify `/health` returns `ok: true`.
2. Validate one authenticated read endpoint.
3. Confirm no migration drift (same `migration_head` expected).

## Data safety notes
- Migrations are idempotent and schema-tracked.
- Rollback should not include destructive schema changes without a dedicated downgrade script.
- Keep staged migrations additive to reduce rollback risk.
