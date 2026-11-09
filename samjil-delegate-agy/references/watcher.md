# Watcher reference

The watcher is a background PowerShell process that takes tasks from an inbox folder and runs `agy` for each one. Files live under `%USERPROFILE%\.samjil\delegate-agy\`.

## Status

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/sub/ensure-agy-running.ps1" -CheckOnly -StaleThresholdSeconds 0
```

| Output | Exit | Meaning |
|---|---|---|
| `ALIVE` | 0 | running |
| `DEAD` | 1 | not running: start it |
| `MANUAL_STOP` | 2 | the user stopped it with `stop-agy.ps1`: ask before starting |

Anything else (empty output, error) means the check failed. Do not read that as "running". Ask the user to run the installer (`install.ps1`) again.

## Start (hidden, no console window)

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/sub/ensure-agy-running.ps1" -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0
```

After `MANUAL_STOP` and the user's yes, first delete `runtime\logs\manual_stop.flag`. Poll `-CheckOnly` every 3 s for up to 30 s. If it never becomes `ALIVE`, do the work directly and point the user to `runtime\logs\watchdog.log` and `watcher.log`.

Do not start it with `start-agy.ps1` (opens a console window) unless the user wants a visible window.

## Stop

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/stop-agy.ps1"` stops it after the current task and writes `manual_stop.flag` so nothing restarts it.

## Limits and failure handling

- At most 5 tasks run at the same time (`AGY_MAX_PARALLEL`).
- One agy call is cut off after 30 minutes, or after 5 minutes with no new step. If the final answer was already written the watcher recovers it automatically.
- If agy fails or hits its quota, do the work directly. If a model you chose with `@model` is out of quota the watcher fails instead of switching models: ask the user whether to retry with the default models or to do it yourself.
- Results and usage are stored in `runtime\logs\agy.db` (SQLite). Logs: `runtime\logs\watcher.log`.

## Dashboard (optional)

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/viewer/ensure-viewer-running.ps1"` starts a local page at `http://127.0.0.1:8787` showing every delegated task, answers and token use. Stop it with `-Stop`.
