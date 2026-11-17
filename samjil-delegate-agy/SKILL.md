---
name: samjil-delegate-agy
description: "Delegate implementation, fixes, refactors, tests and UI work that Claude can specify, plus bulky simple jobs (log or document summaries, translation, the same edit across many files, format conversion), to the Antigravity CLI (agy) on Gemini 4 models through a local watcher to save Claude quota, and consult Argon before very complex decisions. Claude keeps work that needs the conversation's context, one- or two-line edits, and the final call on security, auth, payments and migrations. Use when the user says 'delegate', 'ask agy', 'let agy do it', 'save quota', or the work fits that description. Windows only; needs a one-time local runtime install (see Setup)."
license: MIT
compatibility: "Windows 10/11 with Windows PowerShell 5.1, Claude Code, and the Antigravity CLI (agy) installed and signed in."
metadata:
  version: "2.0.0"
  homepage: "https://github.com/samjil/agy-agent"
---

# samjil-delegate-agy

Delegate to the Antigravity CLI (`agy`) work you can specify exactly, review everything that comes back, and keep for yourself what needs this conversation. Goal: spend less Claude quota without lowering quality.

Measured on the author's PC (2026-11-17, test tasks with hidden tests): Gemini 4 Hydrogen medium finished a 4-file feature in 93 s (17/17 tests), a 4-function task in 61 s (11/11); 3.8 Flash medium needed 562 s and 248 s for the same work at 5x the tokens. Argon, Orchestrator and Hydrogen Extra scored the same but were 2-4x slower on clearly specified work; they pay off only where the thinking is hard. Every Claude call re-reads the whole conversation, so keep each delegation to a few calls.

## 0. Setup check (do this first, every conversation)

Check that the runtime exists:

```bash
test -f "$USERPROFILE/.samjil/delegate-agy/scripts/submit-task.ps1" && echo READY || echo MISSING
```

- `READY`: continue.
- `MISSING`: this skill is only the rules; the local runtime (watcher and scripts) comes from the public repository <https://github.com/samjil/agy-agent>. Tell the user in one line and ask before installing. With their OK, run its `install.ps1`:
  - from a local copy of the repository (a clone or an unzipped download) that the user points you to: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<repo folder>\install.ps1"`, or
  - straight from the web: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/samjil/agy-agent/main/install.ps1 | iex"`.

  Do not download or run scripts from anywhere else. Until it is installed, do the work yourself.

If `agy` itself is missing or not signed in, the installer says so. The user fixes that once (install Antigravity CLI, run `agy` once to sign in). Never install or sign in for them.

## 1. What to delegate, and on which tier

| Delegate | Keep (do it yourself) |
|---|---|
| Implementation, fixes, refactors, tests, UI work whose spec you can write (paths, AS-IS -> TO-BE, names, checks) | Work that needs this conversation's context |
| Bulky simple work: long logs or documents, translation, the same edit across many files, format conversion, test data, first-pass search | A one- or two-line edit (the brief costs more than the edit) |
| | The final decision on security, auth, payments, migrations and anything hard to undo (agy may draft; you decide and review line by line) |

Pick a tier and write it as `@model: <tier>` (details and fallbacks: `references/models.md`):

| Tier | When | Model | Wait limit |
|---|---|---|---|
| `quick` | lookups, summaries, translation, format conversion, short questions | Hydrogen low | 3 min |
| `build` | clearly specified implementation, a few files, tests, repeated edits (**default for code**) | Hydrogen medium | 8 min |
| `build-hard` | `build` with many edge cases, or a `build` that failed once | Hydrogen high | 12 min |
| `feature` | a multi-file feature where agy must also split the work and plan the steps | Orchestrator (Argon) | 20 min |
| `think` | little editing, deep reasoning: design review, root cause of a hard bug, consultation | Argon high | 20 min |
| `deep` | few files but hard logic: algorithms, concurrency or races, parsers or state machines, numeric precision, a measured performance target, fixing a bug whose cause Argon found, re-sending a failed `build-hard` | Hydrogen Extra (xhigh) | 20 min |

- Choose `deep` yourself whenever its conditions hold; the user does not have to ask. Do not use it for clearly specified ordinary logic (slower and 2-3x the tokens for the same result).
- `build` vs `feature`: if you write the per-file spec yourself, it is `build`/`build-hard`, however many files. Use `feature` only when agy should plan the split.
- Without `@model` the watcher picks only `quick` (short read-only) or `build` (changes files). It never picks a higher tier.
- 3.8 Flash is only the last fallback when the Gemini 4 models are blocked; a result from it starts with an `[알림]` line. Review it more carefully.

If the user asks to delegate and the job belongs on the "keep" side, say so in one line and offer to do it directly; follow the user's choice. agy has no web search. Never trust factual claims from agy without checking.

### Balance the two quotas

Use the Claude and agy subscriptions at a similar pace relative to the time left in each window (not 50:50, just not far apart). A line `[한도 균형] <mode> ...` and an advice line come with each prompt (hook) and from `quota-balance.ps1`; follow the mode:

| Mode | When | What changes |
|---|---|---|
| `agy-more` | Claude is burning faster than agy | Delegate multi-file work, tests, docs and code-exploration bundles. Hand the delegation procedure to a subagent above 80k context. One- or two-line edits stay direct (a delegation costs at least two Claude calls). |
| `agy-max` | Claude 5-hour limit 90% or more used | Delegate everything delegable; Claude only writes briefs, reviews and talks to the user. Subagent above 30k context. |
| `balanced` | similar pace | The rules above as they are. |
| `claude-more` | agy is burning faster | Still delegate whatever meets the rules above; only pick the lighter tier when it gives the same result (`quick`/`build`), and use `deep`/`feature` only when really needed. Claude having more quota left is never a reason to skip a delegation. |
| `no-agy` | agy Gemini 5-hour under 10% or weekly under 5% | Do not delegate until it resets. |

If the line also says Argon is tight, keep `think`/`feature` to required consultations and split the work yourself into `build`/`build-hard`.

Claude's own limits are visible only to you (the desktop app's usage tool). When the line says the Claude numbers are missing or older than 30 minutes and the request is real work, read your usage once in the same message as your first other call, then put this before your next shell command (same call, no extra round trip): `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/sub/quota-balance.ps1" -Claude5hUsed <N> -Claude5hResetsAt <ISO> -ClaudeWeekUsed <N> -ClaudeWeekResetsAt <ISO> ;`. Without that tool, the mode uses agy numbers only.

## 2. Consult Argon before very complex decisions

For a design across several modules, a structural change that is hard to undo, a bug whose cause you cannot see, or a decision between two or more directions that is hard to call: consult Argon (`think`) at least once before you decide. Use the `samjil-handoff` channel (its default model is `think`).

- Send: the problem, the options, your recommendation and why, **the relevant file paths and the constraints** (Argon does not know this conversation), and always: "Do not simply agree. Focus on objections, missed edge cases and alternatives; list what you would change as numbered items."
- One round trip as a rule, two at most. These do not count toward the 3-call budget of a delegation.
- If the consultation fails or passes the 20-minute limit, do not ask again: decide alone and tell the user you could not consult.
- After deciding, tell the user in one or two lines what you changed because of Argon, and in one line each what you did not take and why. The decision and the responsibility stay with you.
- Hard bug: `think` finds the cause and the fix direction; `deep` makes the fix.

## 3. Delegate: submit, wait up to the tier limit, check

Budget per delegated task: **at most 3 Claude calls** (5 when you escalate once).

1. **Call 1: check the watcher, submit with `-NoWait` and start one background wait in the same message.**
   ```bash
   S="$USERPROFILE/.samjil/delegate-agy/scripts"
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/sub/ensure-agy-running.ps1" -CheckOnly -StaleThresholdSeconds 0   # ALIVE | DEAD | MANUAL_STOP
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/submit-task.ps1" -NoWait <<'CLAUDE_TASK_EOF'
   @cwd: C:\path\to\project
   @model: build
   @reason: one line, why this is delegated
   [1. Goal] one or two lines; say whether it is read-only or edits files
   [2. Spec] file paths (with line numbers), exact AS-IS -> TO-BE, names and values. Do not paste whole files
   [3. Limits] rules that matter for this task, files not to touch. If something is unclear: write [NEED INFO] and a question as the first line of the answer and do not touch that part
   [4. Verify and report] the test/build command; reply as: status, changed files, one-line test result, concerns
   CLAUDE_TASK_EOF
   ```
   The submit prints `[단계] <tier> (<model>) · 대기 한도 <s>` on stderr. Then, in the same message, run the wait in the background (`run_in_background`):
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/submit-task.ps1" -Poll <ID> -CancelOnTimeout` (without `-MaxWaitSec` it waits up to the tier's limit).
   - `DEAD`: start the watcher first (`ensure-agy-running.ps1 -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0`). `MANUAL_STOP` means the user stopped it on purpose: ask before starting, or do the job yourself. Details: `references/watcher.md`.
   - Leave out `@cwd` for tasks that need no files. For tasks that read or write project files, confirm the project folder with the user once per conversation and say that agy runs with permissions skipped inside it (suggest it be under git). Never guess a folder. Before a large edit, save `git diff` somewhere first.
2. **Call 2: read the result and check it in one command**: the `-Poll` output, `git diff --stat` (and the diff you need to read) and the key test command, together in one shell call.
3. **Call 3 (only if needed): fix the remainder yourself.**

**Wait limit = the tier's limit.** If the task is not done by then, the `-CancelOnTimeout` poll cancels it (`===CANCELLED=== <ID>`, exit 4): do the job yourself. Do not poll in a loop. To cancel earlier: `submit-task.ps1 -Cancel <ID>`.

**Escalate once, one step.** If the result fails its tests: `build` -> `build-hard`, `build-hard` -> `deep`, sent once (same brief plus what failed). The two waits together stay under 20 minutes when you started at `build`, 30 minutes when you started at `build-hard`. A failed `deep`, `quick`, `feature` or `think` task is not re-sent: fix it yourself (consult `think` first if the cause is unclear). If agy fails (`===ERROR===`, or the answer reports an agy run failure), check `git diff --stat` for half-done edits and finish directly.

**Large context.** `submit-task.ps1` prints `[컨텍스트 <N>k] ...` on stderr when the conversation context is over about 200k tokens (`AGY_CTX_SUBAGENT_THRESHOLD`). Then hand the delegation procedure (submit, wait, diff review, tests) to one fresh-context subagent running a cheap model, and do only the brief and a final `git diff --stat` check yourself. The subagent reports in at most 5 lines: passed or not, changed files, concerns.

More: several tasks at once (`-NoWait`, then `-Poll <ID1>,<ID2>`, at most 5), `@session`, `@model`, `@upgrade`: `references/brief-and-commands.md` and `references/models.md`.

## 4. Always review what agy returns

Never pass agy output on unchecked. Bar: "as good as if Claude had done it".

- Requirements and spec all met? Nothing invented, nothing skipped?
- Code: read the diff yourself and re-run the key test or build. Do not trust "tests passed" in the report. Check file encoding and line endings when the project cares.
- agy must not commit. The watcher warns at the top of the answer if git state changed. You review the diff and you decide on the commit.
- Facts and numbers: check them or leave them out.
- Do not touch the same files while agy is working on them.

## 5. Leave the reason, add no closing line

Never end an answer with a delegation tag, estimate line or level tag, whether you delegated or not. How each question was handled (direct or delegated, models, time, tokens) is collected from the conversation record and shown on the viewer's "실측 통계" page (`http://127.0.0.1:8787/#/stats`). Only the reason is yours to leave, in one short line:

- **Direct:** prefix the question's first shell command with the note, in the same call: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/note-choice.ps1" -Mode direct -Reason "two-line edit, brief costs more" ; <your command>`. Never make a separate call for it. A question that needs no shell command leaves no note.
- **Delegated:** add `@reason: <one line>` to the brief's directive lines. It is recorded and not sent to agy.

Nothing enforces this; a missing reason shows as "기록 없음". When you answer in Korean, the Korean rules and wording are in `references/full-rules-ko.md`.

## 6. Switch off, remove, more

- Stop the watcher: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/stop-agy.ps1"`.
- Remove the skills, tools and the session hook: run `uninstall.ps1` from the same repository (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/samjil/agy-agent/main/uninstall.ps1 | iex"` or the local file). Task history under `~/.samjil` is kept; delete it by hand to remove that too.
- Models and tiers live in `~/.samjil/delegate-agy/config/models.json` (overwritten on update). Put your own changes in `models.local.json` next to it.
- Dashboard of delegated tasks: `http://127.0.0.1:8787` (start it with `viewer/ensure-viewer-running.ps1` under `~/.samjil`).
- Troubleshooting, logs, stuck tasks: `references/watcher.md`.
- The same rules in Korean, with more detail: `references/full-rules-ko.md`. Read only when a case above does not cover it.
