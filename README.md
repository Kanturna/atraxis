# atraxis
gravity based sim

## Tests
Run GUT from the repo root with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-gut-tests.ps1
```

The script uses `godot_console.exe` and a repo-local `.test_env` folder for
`APPDATA` and `LOCALAPPDATA` so headless test runs do not crash on `user://logs`.
