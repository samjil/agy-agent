# Brief and command reference

## Directives (top of the instruction, any order, before the body)

| Line | Meaning |
|---|---|
| `@cwd: <folder>` | Let agy read and write this folder. Repeat the line for several folders. A missing folder fails the task before agy starts. Sticky per `@session`. |
| `@model: <id>` | Use exactly this model (see `models.md`). Without it the watcher picks an effort level from the request. |
| `@session: <name>` | Continue the same agy conversation across several submissions (feedback after review, multi-step jobs). Use a short, stable name. Independent tasks should not share a session. |
| `@upgrade: true` | With `@session` + a higher `@model`: start a new conversation and paste the previous question/answer pairs into it. |
| `@raw: true` | Do not append the standard rules (translation, data conversion). |

For tasks with `@cwd` the watcher appends these rules to the prompt automatically, so do not repeat them: do not commit, run commands in the foreground, touch only needed files, and write the final reply in the configured language (`reply-language.txt`, `auto` by default = the Windows region setting; write a language name such as `English` into it or set `AGY_REPLY_LANGUAGE` to fix it).

## submit-task.ps1

```
submit-task.ps1                 instruction on stdin (use a quoted heredoc so $ and ` are not expanded)
submit-task.ps1 -File <path>    instruction from a file
submit-task.ps1 -NoWait         submit only, print "submitted: <ID>"
submit-task.ps1 -Poll <ID,...>  wait for results of submitted tasks
submit-task.ps1 -WaitSeconds N  how long one call waits (default 170)
```

| Output | Exit | Meaning |
|---|---|---|
| `===RESULT=== <ID>` + text | 0 | Answer exists. Read it: a failure reason can come as the answer. |
| `===ERROR=== <ID>` + text | 1 | No answer, only an error log. |
| `===PENDING=== <ID> ...` | 2 | Still running. Do not resubmit. `-Poll <ID>` again. |
| message | 3 | Runtime missing or empty instruction. |

PowerShell instead of bash: pipe a single-quoted here-string:
`@'` ... `'@ | powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.samjil\delegate-agy\scripts\submit-task.ps1"`

Before sending, the script lints the brief and prints `[brief check] ...` warnings (missing verification step, no limits, pasted file bodies). Warnings do not block the task. Turn off with `AGY_BRIEF_LINT=off`.

## Parallel tasks

Submit each with `-NoWait`, then `-Poll id1,id2`. At most 5 run at once. Tasks with the same `@session` and overlapping `@cwd` run one after another. Give different folders different session names.

## Good briefs

- Four parts: goal, spec, limits, verify and report. 600 to 1800 characters is typical.
- Put exact values in the spec (file:line, function names, AS-IS to TO-BE). agy starts empty every time and cannot ask questions.
- Ask for a report file path for long logs and a short final answer: status, changed files, test result, concerns.
- Do not forbid things agy can do (for example "do not open a browser"). agy can use a browser through its MCP tools to check a local page. Forbid only what is dangerous: commits, edits outside the task.
- Keep each task small: a few files, about 10 minutes. Long wide jobs: ask agy to create the result file first and append findings as it goes.
- A task reported as error can still be running (`waiting for background task`). Check `logs/watcher.log` and `git status` twice before touching that repository.

## Git safety

If `@cwd` is a git repository the watcher compares HEAD, branch and stash count before and after. If agy changed git state, a warning banner is added on top of the answer with recovery commands. It does not undo anything automatically. Uncommitted changes are saved first as `refs/samjil/snapshots/<task id>` (latest 20); restore with `git stash apply <ref>`. Turn off with `AGY_GIT_GUARD=off` (restart the watcher).
