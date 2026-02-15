# Release Checklist

## 1) Verify Render Blueprint
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File tool/verify_render_blueprint.ps1
```

Bash:
```bash
bash tool/verify_render_blueprint.sh
```

## 2) Run Release Gate
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File tool/release_gate.ps1
```

Bash:
```bash
bash tool/release_gate.sh
```

Convenience wrapper (staging-first + optional production):
```powershell
powershell -ExecutionPolicy Bypass -File tool/release.ps1
powershell -ExecutionPolicy Bypass -File tool/release.ps1 -IncludeProd
```
```bash
bash tool/release.sh
INCLUDE_PROD=1 bash tool/release.sh
```

## 3) Deploy on Render
1. Confirm `render.yaml` is up to date on `main`.
2. In each API service (`hail-o-api`, `hail-o-api-staging`) and CI worker (`hail-o-ci`):
   - Runtime: `Docker`
   - Root Directory: `.`
   - Dockerfile Path:
     - API services: `backend/Dockerfile`
     - CI worker: `Dockerfile.ci`
   - Start Command override: empty (use Dockerfile `CMD`)
   - Docker Command override: empty (use Dockerfile `CMD`)
3. Trigger deploy from latest `main`.

## 4) Verify Health
Production:
```bash
curl -i https://hail-o-api.onrender.com/health
curl -i https://hail-o-api.onrender.com/api/healthz
```

Staging:
```bash
curl -i https://hail-o-api-staging.onrender.com/health
curl -i https://hail-o-api-staging.onrender.com/api/healthz
```

## 5) Run Smoke Scripts
Staging (default):
```powershell
powershell -ExecutionPolicy Bypass -File tool/smoke_backend.ps1
```
```bash
bash tool/smoke_backend.sh
```

Production:
```powershell
$env:HAILO_API_BASE_URL='https://hail-o-api.onrender.com'
$env:ENV='production'
$env:HAILO_ALLOW_PROD_SMOKE='1'
powershell -ExecutionPolicy Bypass -File tool/smoke_backend.ps1
```
```bash
HAILO_API_BASE_URL=https://hail-o-api.onrender.com ENV=production HAILO_ALLOW_PROD_SMOKE=1 bash tool/smoke_backend.sh
```
