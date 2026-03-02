# Windows Test Setup

HAIL-O's Flutter test suite uses `sqflite_common_ffi` for local SQLite-backed tests.
On Windows, those tests need `sqlite3.dll` available.

## Recommended setup

1. Install the SQLite tools bundle for Windows from the official SQLite downloads page.
2. Ensure `sqlite3.dll` is available in one of these locations:
   - Anywhere on your `PATH`
   - The repo root working directory
   - `backend\sqlite3.dll` (the Flutter test bootstrap will use this bundled copy when present)

If `sqlite3.dll` is missing, DB-backed suites will print:

`Skipping DB tests: sqlite3.dll not found. Install sqlite-tools and add sqlite3.dll to PATH.`

## Commands

Frontend-only:

```powershell
flutter test -r expanded
```

Backend-only:

```powershell
Set-Location .\backend
dart pub get
dart test -r expanded
```

Repo root convenience:

```powershell
.\ops\test_all.ps1
```

Windows frontend convenience:

```powershell
.\ops\test_windows.ps1
```
