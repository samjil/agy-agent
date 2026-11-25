---
name: samjil-delegate-agy
description: "Load BEFORE starting any task that creates or edits code, docs, config files or Office files (xlsx, pptx), and BEFORE handing such work to the Agent tool, even when the user never says 'delegate'. Delegates implementation, fixes, refactors, tests, UI work and bulky simple jobs (summaries, translation, the same edit across many files, format conversion) to the Antigravity CLI (agy) on Gemini 4 Hydrogen/Neon/Carbon tiers (@cmd/@mode options) through a local watcher to save Claude quota, and consults Neon (think) or Carbon (think-carbon) before very complex decisions. agy comes before Claude subagents: use the Agent tool only for what agy cannot do (DB queries, VPN, browser, mail, judgment that needs this conversation) or after agy fails or times out. Claude keeps context-bound work, one- or two-line edits, and the final call on security, auth, payments and migrations. Also use on 'delegate', 'ask agy', 'save quota'. Windows only; needs a one-time local runtime install (see Setup)."
license: MIT
compatibility: "Windows 10/11 with Windows PowerShell 5.1, Claude Code, and the Antigravity CLI (agy) installed and signed in."
metadata:
  version: "2.0.0"
  homepage: "https://github.com/samjil/agy-agent"
---

# samjil-delegate-agy

Delegate to the Antigravity CLI (`agy`) as much as you can: anything you can specify exactly goes to agy, you review everything that comes back, and you keep only what needs this conversation. Goal: spend less Claude quota without lowering quality.

**Default: delegate.** Before doing work yourself, ask "can I write a spec for this?" If yes, delegate it. Doing it yourself is the exception and needs one of the reasons in the "Keep" column below.

**agy before the Agent tool.** Claude subagents (the Agent tool) are not a delegation target for work agy can do. Use the Agent tool only when agy cannot do the job (table below) or when agy failed or timed out on it. A subagent that submits to agy, waits and reviews (section 3, "Large context") is fine: the work itself still goes to agy. A `PreToolUse` hook on the Agent tool stops the first non-read-only Agent call in each session with this reminder; re-issue the same call if the job is on the right-hand side.

| agy can do it (delegate) | agy cannot (Claude or a Claude subagent) |
|---|---|
| The same edit across many md files (remove local paths, rename terms, renumber) | Queries against production or development databases |
| Text changes in xlsx (openpyxl) or pptx (python-pptx) | SSH or anything that needs a VPN |
| A well-scoped web view refactor, writing vitest/Jest/pytest tests | Browser work (GitLab/GitHub MR pages, web consoles), reading mail |
| Code, config and doc changes in a folder outside this repository (set `@cwd`) | Design calls that need the user's answers as you go |
| Read-only exploration or summaries of many files | Facts that need web search (agy has none) |

All Gemini models share one "Gemini Models" quota. **Neon** is the balanced main model (AA Intelligence 60 high / 61 xhigh; Coding Agent Index #1 at 58.64; ~101–110 tok/s, first token ~41 s; ~30–32% less quota than Carbon; $3/$15) and should handle 80%+ of real development (multi-file edits, refactors, debugging). **Hydrogen** is the fast tier (AA 51 high / 54 xhigh; ~165–170 tok/s, first token ~20 s; 50%+ less quota than Carbon; $1.50/$7.50) for boilerplate, unit tests, simple UI, summaries and clear repetitive work. **Carbon** is the flagship with deepest thinking (AA 60 high; ~56 tok/s, first token ~73 s; heaviest quota cost, baseline 100%; $4/$20) — use only for architecture/initial design, unexplained multi-service bugs, hard legacy logic, final review before big changes, or problems Neon could not solve. **Orchestrator (Neon)** plans/reviews with Neon and executes with Hydrogen; **Orchestrator (Carbon)** reads dependencies and designs read-only with Carbon while Hydrogen implements (~24% less quota and ~19% faster than Carbon alone; executor is always Hydrogen). Every Claude call re-reads the whole conversation, so keep each delegation to a few calls.

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

| Delegate (default) | Keep (do it yourself) — only these |
|---|---|
| Implementation, fixes, refactors, tests, UI work whose spec you can write (paths, AS-IS -> TO-BE, names, checks) | Work that needs this conversation's context and cannot be written into a brief |
| Bulky simple work: long logs or documents, translation, the same edit across many files, format conversion, test data, first-pass search or code exploration | A one- or two-line edit (the brief costs more than the edit) |
| Reading and summarizing large files or many files before you decide something | The final decision on security, auth, payments, migrations and anything hard to undo (agy may draft; you decide and review line by line) |
| Writing or updating tests and docs for code you just changed | Talking to the user, and reviewing what agy returns |

- When in doubt, delegate. A task that "needs some context" usually needs only a few facts: put them in the brief instead of keeping the task.
- Split a big job into briefs and send them in parallel (`-NoWait`, at most 5) instead of doing part of it yourself.
- Keep for yourself only the parts that truly need you; delegate the rest of the same request.

Pick a tier and write it as `@model: <tier>` (details and fallbacks: `references/models.md`):

| Tier | When | Model | Wait limit |
|---|---|---|---|
| `quick` | lookups, summaries, translation, format conversion, short questions | Hydrogen low | 3 min |
| `build` | boilerplate, unit tests, simple UI, clearly specified repeated edits (**default for code**) | Hydrogen medium | 8 min |
| `build-hard` | multi-file edits, refactors, debugging, or `build` with many edge cases / failed once | Neon medium | 12 min |
| `feature` | a multi-file feature where agy must also split the work and plan the steps (Neon plans/reviews + Hydrogen executes) | Orchestrator (Neon) | 20 min |
| `feature-carbon` | hard architecture/initial design across multiple files (Carbon designs read-only + Hydrogen implements) | Orchestrator (Carbon) | 20 min |
| `think` | design review, root cause of a hard bug, consultation (handoff default; Neon) | Neon high | 20 min |
| `think-carbon` | architecture/initial design, unexplained multi-service bug, hard legacy logic, final review before big changes — problems Neon could not solve | Carbon high | 20 min |
| `deep` | few files but extreme logic: algorithms, concurrency or races, parsers or state machines, numeric precision, a measured performance target, fixing a bug whose cause `think`/`think-carbon` found, re-sending a failed `build-hard` | Neon Extra (xhigh) | 20 min |

- Choose `deep` yourself whenever its conditions hold; the user does not have to ask. Do not use it for clearly specified ordinary logic (slower and higher token cost for the same result). If `xhigh` returns an effort/thinking-level HTTP 400 on an account, the watcher falls back to `neon-high`.
- `build` vs `build-hard` vs `feature`/`feature-carbon`: clear boilerplate/tests/simple UI/spec on a few files -> `build`; multi-file edits, refactors, debugging or retry -> `build-hard` (Neon medium); use `feature` (Orchestrator Neon) or `feature-carbon` (Orchestrator Carbon) when agy should plan the split itself.
- **Neon by default (80%+ of work); Carbon (`think-carbon` / `feature-carbon`) only for architecture, unexplained multi-module bugs, hard legacy logic, final review, or when Neon failed; Carbon costs the most quota; Hydrogen for clear repetitive work.**
- Without `@model` the watcher picks only `quick` (short read-only) or `build` (changes files). It never picks a higher tier.

If the user asks to delegate and the job belongs on the "keep" side, say so in one line and offer to do it directly; follow the user's choice. agy has no web search. Never trust factual claims from agy without checking.

**Unsure how the agy CLI itself works** (flags, slash commands, output fields, settings, file locations)? Check `agy --help`, `agy help <subcommand>` and `agy models` first; if that does not answer it, ask agy before guessing or asking the user: a read-only `@model: quick` delegation without `@cwd` ("answer from what you know, no tools, say when unsure, give exact flag/field names"). When the Gemini 5-hour quota is used up, ask a Claude model inside agy directly (its quota is separate): `agy -p "<question>" --model claude-sonnet-5-5-low`. Treat the answer as unverified until you have run the flag or command once yourself.

### Optimize execution with slash commands (`@cmd` / `@mode`)

Pair `@model:` with an optional `@cmd:` or `@mode:` directive when the task shape warrants it (details: `references/brief-and-commands.md`):

| Directive | Best for | Behavior & safeguards |
|---|---|---|
| `@cmd: goal` | Clear spec that needs full end-to-end execution | Runs autonomously until completion without mid-turn pauses; watcher strips internal completion markers. |
| `@cmd: swarm` | Wide work splitting cleanly across **non-overlapping files** + independent verification | Spawns parallel workers + Verifier on shared board. Watcher enforces `workspace:"inherit"` (no commits) and 20 min min wait. Uses a lot of agy quota: only when the task shape needs it. |
| `@cmd: run-workflow` | Uniform fan-out across many files or strict multi-stage Python orchestration | Writes/runs Python `parallel()`/`pipeline()`. Watcher enforces `workspace:"inherit"` and 20 min min wait. Uses a lot of agy quota: only when the task shape needs it. |
| `@cmd: boost` | Single extremely hard bug, race condition, or algorithm | Deep iterative solve -> challenge -> re-verify pipeline (20 min min wait). Uses a lot of agy quota: only when the task shape needs it. |
| `@cmd: browser` | Live frontend UI verification, visual diff, console/network inspection | Invokes Chrome DevTools browser subagent on localhost. |
| `@cmd: plan` or `@mode: plan` | Read-only implementation blueprint / architecture proposal | Read-only planning before editing (if `@mode: plan`, omit `@cmd: plan`). |

- **`Orchestrator` vs `/swarm` vs `/run-workflow`**: daily multi-file feature in one flow -> `feature`/`feature-carbon`; independent non-overlapping file edits needing cross-verification -> `@cmd: swarm`; mechanical N-item fan-out or strict sequential schema stages -> `@cmd: run-workflow`. Prefer several `-NoWait` `build` tasks when you already wrote exact per-file specs.
- **Interactive TUI commands & consumer-plan note**: `/teamwork`, `/grill-me`, `/rewind`, `/fork`, `/btw`, `/compact`, `/learn`, `/permissions`, `/tasks`, `/agents`, `/resume` are **interactive-TUI only** (rejected by headless watcher and `agy-brief-lint`). Also, Antigravity consumer plans (Google AI Pro/Ultra) officially scope `agy -p` to direct scripting rather than third-party agent wrapping — for multi-milestone `/teamwork`, interactive `/grill-me`, or when you prefer direct execution, write a clean spec `.md` file and let the user run `@spec.md` interactively in their own `agy` session.

## 2. Consult Neon (`think`) or Carbon (`think-carbon`) before very complex decisions

For a design across several modules, a structural change that is hard to undo, a bug whose cause you cannot see, or a decision between two or more directions that is hard to call: consult `think` (Neon high, default) or `think-carbon` (Carbon high) at least once before you decide. Use the `samjil-handoff` channel (default `think`; set `위임모델: think-carbon` in message front-matter for a second opinion, hardest architecture/design calls, or final review).

- Send: the problem, the options, your recommendation and why, **the relevant file paths and the constraints** (the reviewer does not know this conversation), and always: "Do not simply agree. Focus on objections, missed edge cases and alternatives; list what you would change as numbered items."
- One round trip as a rule (two at most, e.g., when getting a Carbon second opinion after Neon on a critical architectural call). These do not count toward the 3-call budget of a delegation.
- If the consultation fails or passes the 20-minute limit, do not ask again: decide alone and tell the user you could not consult.
- After deciding, tell the user in one or two lines what you changed because of the consultation, and in one line each what you did not take and why. The decision and the responsibility stay with you.
- Hard bug: `think` (or `think-carbon` for unexplained multi-service/legacy bugs) finds the cause and the fix direction; `deep` (or `@cmd: boost` on `deep`/`think`) makes the fix.

## 3. Delegate: submit, wait up to the tier limit, check

Budget per delegated task: **at most 3 Claude calls** (5 when you escalate once).

1. **Call 1: check the watcher, submit with `-NoWait` and start one background wait in the same message.**
   ```bash
   S="$USERPROFILE/.samjil/delegate-agy/scripts"
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/sub/ensure-agy-running.ps1" -CheckOnly -StaleThresholdSeconds 0   # ALIVE | DEAD | MANUAL_STOP
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/submit-task.ps1" -NoWait <<'CLAUDE_TASK_EOF'
   @cwd: C:\path\to\project
   @model: build
   @cmd: goal                      # optional: goal | swarm | run-workflow | boost | browser | plan (see references/brief-and-commands.md)
   @reason: one line, why this is delegated
   [1. Goal] one or two lines; say whether it is read-only or edits files
   [2. Spec] file paths (with line numbers), exact AS-IS -> TO-BE, names and values. Do not paste whole files
   [3. Limits] rules that matter for this task, files not to touch. If something is unclear: write [NEED INFO] and a question as the first line of the answer and do not touch that part
   [4. Verify and report] the test/build command; reply as: status, changed files, one-line test result, concerns
   CLAUDE_TASK_EOF
   ```
   The submit prints `[단계] <tier> (<model>) · 대기 한도 <s>` on stderr. Then, in the same message, run the wait in the background (`run_in_background`):
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/submit-task.ps1" -Poll <ID> -CancelOnTimeout` (without `-MaxWaitSec` it waits up to the tier's limit).
   - `DEAD` or `MANUAL_STOP`: submit anyway — `submit-task.ps1` starts the watcher, or runs the task directly when the watcher cannot start. Never ask the user and never do the job yourself just because the watcher is off. Details: `references/watcher.md`.
   - Leave out `@cwd` for tasks that need no files. For tasks that read or write project files, confirm the project folder with the user once per conversation and say that agy runs with permissions skipped inside it (suggest it be under git). Never guess a folder. Before a large edit, save `git diff` somewhere first.
   - `@cwd` may point outside the current repository, for example a synced documents folder such as `@cwd: D:\OneDrive - Example\Projects\my-webview`. The same rules apply (confirm the folder with the user; if it is not under git, copy the files you will change somewhere first).
   - In the Claude desktop app (when `mcp__ccd_session_mgmt__get_usage` exists), call it in parallel with the first tool call of **every** question that uses tools (direct or delegated), at most once per 10 minutes, and prefix the next shell command with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/note-claude-limits.ps1" -FiveHourPct <percentUsed> -FiveHourReset <resetsAt> -WeekPct <percentUsed> -WeekReset <resetsAt> ;` from `plan.windows` (5-hour limit / Weekly · all models). Skip when missing or empty.
2. **Call 2: read the result and check it in one command**: the `-Poll` output, `git diff --stat` (and the diff you need to read) and the key test command, together in one shell call.
3. **Call 3 (only if needed): fix the remainder yourself.**

**Wait limit = the tier's limit.** When the limit passes, the `-CancelOnTimeout` poll checks activity: it keeps waiting while agy is still making progress and cancels only when there has been no progress for 5 minutes (or after the 2-hour hard cap; `===CANCELLED=== <ID>`, exit 4): do the job yourself. Do not poll in a loop. To cancel earlier: `submit-task.ps1 -Cancel <ID>`.

**Escalate once, one step.** If the result fails its tests: `build` -> `build-hard`, `build-hard` -> `deep`, sent once (same brief plus what failed). The two waits together stay under 20 minutes when you started at `build`, 30 minutes when you started at `build-hard`. A failed `deep`, `quick`, `feature` or `think` task is not re-sent: fix it yourself (consult `think` first if the cause is unclear). If agy fails (`===ERROR===`, or the answer reports an agy run failure), check `git diff --stat` for half-done edits and finish directly.

**Large context.** When the context is over the limit (200k; `AGY_CTX_SUBAGENT_THRESHOLD` changes it), the prompt hook adds `[컨텍스트 <N>k] ...` before you start. If that question ends up delegated, the work still goes to agy: write the brief yourself and give it to one fresh-context subagent running a cheap model, which submits it to agy with `submit-task.ps1`, waits, reviews the diff and runs the tests (it does the job itself only when agy cannot: DB, VPN, browser, mail); you only read its report (at most 5 lines: passed or not, changed files, concerns) and do a final `git diff --stat`. Put this in the subagent's prompt: "wait with exactly one background `submit-task.ps1 -Poll <ID> -CancelOnTimeout` and end your turn; you are resumed only after all your background commands have finished, so never start a second background command that watches an output file (until/while + sleep loops) — if its condition never matches you stay asleep forever; wait for anything else in the foreground with a timeout". If you only see the warning from `submit-task.ps1` after submitting, the task is already queued: do not start your own poll; hand the task ID and the test command to such a subagent for the wait and the review. In the Claude desktop app, the subagent calls `mcp__ccd_session_mgmt__get_usage` and runs `note-claude-limits.ps1` if it has the tool; otherwise the main session does it in its final `git diff --stat` call.

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

- **Direct:** prefix the question's first shell command with the note, in the same call: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/note-choice.ps1" -Mode direct -Reason "two-line edit, brief costs more" ; <your command>`. When also recording desktop usage (`note-claude-limits.ps1`), chain both prefixes in one command (`note-choice.ps1 ... ; note-claude-limits.ps1 ... ; <your command>`). Never make a separate call for either. A question that needs no shell command leaves no note.
- **Delegated:** add `@reason: <one line>` to the brief's directive lines. It is recorded and not sent to agy.

Nothing enforces this; a missing reason shows as "기록 없음". When you answer in Korean, the Korean rules and wording are in `references/full-rules-ko.md`.

## 6. Switch off, remove, more

- Stop the watcher: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/stop-agy.ps1"`.
- Remove the skills, tools and the session hook: run `uninstall.ps1` from the same repository (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/samjil/agy-agent/main/uninstall.ps1 | iex"` or the local file). Task history under `~/.samjil` is kept; delete it by hand to remove that too.
- Models and tiers live in `~/.samjil/delegate-agy/config/models.json` (overwritten on update). Put your own changes in `models.local.json` next to it.
- Dashboard of delegated tasks: `http://127.0.0.1:8787` (start it with `viewer/ensure-viewer-running.ps1` under `~/.samjil`).
- Troubleshooting, logs, stuck tasks: `references/watcher.md`.
- The same rules in Korean, with more detail: `references/full-rules-ko.md`. Read only when a case above does not cover it.
