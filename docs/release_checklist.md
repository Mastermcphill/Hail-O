# Release Checklist

## 1) Run Release Gate
PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File tool/release_gate.ps1
```

Bash:
```bash
bash tool/release_gate.sh
```

## 2) Deploy on Render
1. Confirm `render.yaml` is up to date on `main`.
2. In each API service (`hail-o-api`, `hail-o-api-staging`):
   - Runtime: `Docker`
   - Root Directory: `.`
   - Dockerfile Path: `backend/Dockerfile`
   - Start Command override: empty (use Dockerfile `CMD`)
3. Trigger deploy from latest `main`.

## 3) Verify Health
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

## 4) Run Smoke Scripts
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
