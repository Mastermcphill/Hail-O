# Contributing

## Branch Strategy
- Base branch: `main`
- Feature branches: `feature/<short-name>`
- Bugfix branches: `fix/<short-name>`
- Hotfix branches: `hotfix/<short-name>`

## Commit Convention
Use Conventional Commits:
- `feat: ...`
- `fix: ...`
- `chore: ...`
- `docs: ...`
- `refactor: ...`
- `test: ...`

Example:
```text
feat(auth): add provider-backed auth session bootstrap
```

## Local Validation Commands
From repo root:
```powershell
dart format lib test backend
flutter analyze
flutter test
Set-Location backend
dart analyze
dart test
Set-Location ..
```

## Pull Request Requirements
- Keep changes scoped and avoid unrelated refactors.
- Add/update tests for behavior changes.
- Update docs for runtime flags, deployment, or operational changes.
- Ensure CI is green before requesting review.

## Architecture Rules
- App-wide state: `Provider` + `ChangeNotifier`.
- Local UI-only state: `StatefulWidget` + `setState`.
- Do not introduce Riverpod/Bloc/GetX.
