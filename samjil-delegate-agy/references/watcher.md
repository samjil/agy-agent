# Watcher reference

The watcher is a background PowerShell process that takes tasks from an inbox folder and runs `agy` for each one. Files live under `%USERPROFILE%\.samjil\delegate-agy\`.

## Status

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/sub/ensure-agy-running.ps1" -CheckOnly -StaleThresholdSeconds 0
```

| Output | Exit | Meaning |
|---|---|---|
| `ALIVE` | 0 | running |
| `DEAD` | 1 | not running: submit anyway (`submit-task.ps1` starts it, or runs the task directly when it cannot start) |
| `MANUAL_STOP` | 2 | stopped with `stop-agy.ps1`: submit anyway — `submit-task.ps1` clears `manual_stop.flag` and starts it, or runs the task directly when it cannot start. Never ask or do the job yourself just because the watcher is off |

Anything else (empty output, error) means the check failed. Do not read that as "running". Ask the user to run the installer (`install.ps1`) again.

## Start (hidden, no console window)

`submit-task.ps1` starts the watcher automatically on delegation (clears `manual_stop.flag`, launches hidden, waits up to 15 s for `ALIVE`, and runs the task directly in worker mode if the watcher still does not start). To start the watcher manually without a console window:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/sub/ensure-agy-running.ps1" -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0
```

Do not start it with `start-agy.ps1` (opens a console window) unless the user wants a visible window.

## Stop

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/stop-agy.ps1"` stops it after the current task and writes `manual_stop.flag`. The viewer's auto-restart still respects `manual_stop.flag`; only delegation (`submit-task.ps1`) overrides it.

## Limits and failure handling

- At most 5 tasks run at the same time (`AGY_MAX_PARALLEL`).
- A task you cancel with `submit-task.ps1 -Cancel <ID>` (or `-CancelOnTimeout`) has its worker process tree ended; the watcher closes it as `CANCELLED`, not as a failure.
- One agy call is cut off after 30 minutes (or 2 hours hard cap while active). When no new transcript step appears for `AGY_STALL_SECONDS` (default 300 s), the worker switches to `"checking"` and probes `cli-*.log` for an in-flight model request (`"thinking"`) and tool child process CPU activity (`"tool running"`, excluding MCP node servers), re-probing every 60 s. `"thinking"` is capped at `AGY_THINK_MAX_SECONDS` (default 1200 s = 20 min of total silence with no new transcript step) and `"tool running"` at `AGY_TOOL_MAX_SECONDS` (default 1800 s = 30 min); if silence exceeds either cap, or if no new step and no active signal occur for another `AGY_STALL_GRACE_SECONDS` (default 300 s), the worker stops the process tree and resumes the same conversation (`agy --conversation <id>`) with a status prompt (`"asked"`, up to 2 asks per task); a resumed reply becomes the final answer, a reply starting with `[진행 불가]` is recorded as failed with the answer kept, and stalling past the 2nd ask ends as stalled as before. `submit-task.ps1 -Poll -CancelOnTimeout` treats active probe states (`checking`, `thinking`, `tool running`, `asked`) as progress and does not cancel during them (the 2-hour hard cap still applies). If the final answer was already written the watcher recovers it automatically.
- If agy fails or hits its quota, do the work directly. If a model you chose with `@model` is out of quota the watcher fails instead of switching models: ask the user whether to retry with the default models or to do it yourself.
- Results and usage are stored in `runtime\logs\agy.db` (SQLite). Logs: `runtime\logs\watcher.log`.

## Dashboard (optional)

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/viewer/ensure-viewer-running.ps1"` starts a local page at `http://127.0.0.1:8787` showing every delegated task, answers and token use. Stop it with `-Stop`.
