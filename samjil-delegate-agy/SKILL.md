---
name: samjil-delegate-agy
description: "Delegate implementation, fixes, refactors, tests and UI work that Claude can specify, plus bulky simple jobs (log or document summaries, translation, the same edit across many files, format conversion), to the Antigravity CLI (agy) on Gemini 4 Hydrogen/Neon/Argon models with slash-command optimization (@cmd: goal, swarm, run-workflow, boost, browser, plan; @mode: plan, accept-edits, auto) through a local watcher to save Claude quota, and consult Neon (think) or Argon (think-argon) before very complex decisions. Claude keeps work that needs the conversation's context, one- or two-line edits, and the final call on security, auth, payments and migrations. Use when the user says 'delegate', 'ask agy', 'let agy do it', 'save quota', or the work fits that description. Windows only; needs a one-time local runtime install (see Setup)."
license: MIT
compatibility: "Windows 10/11 with Windows PowerShell 5.1, Claude Code, and the Antigravity CLI (agy) installed and signed in."
metadata:
  version: "2.0.0"
  homepage: "https://github.com/samjil/agy-agent"
---

# samjil-delegate-agy

Delegate to the Antigravity CLI (`agy`) as much as you can: anything you can specify exactly goes to agy, you review everything that comes back, and you keep only what needs this conversation. Goal: spend less Claude quota without lowering quality.

**Default: delegate.** Before doing work yourself, ask "can I write a spec for this?" If yes, delegate it. Doing it yourself is the exception and needs one of the reasons in the "Keep" column below.

Measured on the author's PC (2026-11-17) and vendor/independent benchmarks (2026-11-18): Gemini 4 Hydrogen medium finished a 4-file feature in 93 s (17/17 tests), a 4-function task in 61 s (11/11); 3.8 Flash medium needed 562 s and 248 s at 5x tokens. Among frontier models, **Neon** leads coding/reasoning benchmarks (Artificial Analysis Intelligence Index: medium 55, high 60, xhigh 61; Terminal-Bench 4.1 65.2%; AA Coding Agent Index #1 at 58.6; $3/$15) , while **Argon** (AA ~50–53; Deep SWE 77.9%; $4/$20) excels at long-document exploration, structured domain review and cross-model second opinions. Both Neon and Argon remain first-class tiers (`feature`/`think` vs `feature-argon`/`think-argon`) with cross-family fallbacks. Hydrogen handles `quick`/`build` fast; reserve Neon/Argon tiers for harder edge cases, orchestration, review and deep logic. Every Claude call re-reads the whole conversation, so keep each delegation to a few calls.

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
| `build` | clearly specified implementation, a few files, tests, repeated edits (**default for code**) | Hydrogen medium | 8 min |
| `build-hard` | `build` with many edge cases or complex multi-file edits, or a `build` that failed once | Neon medium | 12 min |
| `feature` | a multi-file feature where agy must also split the work and plan the steps (coding priority) | Orchestrator (Neon) | 20 min |
| `feature-argon` | same multi-file planning/execution from Argon's perspective | Orchestrator (Argon) | 20 min |
| `think` | little editing, deep reasoning: design review, root cause of a hard bug, consultation (coding/reasoning priority) | Neon high | 20 min |
| `think-argon` | design review, second opinion, long-doc/domain analysis using Argon high | Argon high | 20 min |
| `deep` | few files but extreme logic: algorithms, concurrency or races, parsers or state machines, numeric precision, a measured performance target, fixing a bug whose cause `think`/`think-argon` found, re-sending a failed `build-hard` | Neon Extra (xhigh) | 20 min |

- Choose `deep` yourself whenever its conditions hold; the user does not have to ask. Do not use it for clearly specified ordinary logic (slower and higher token cost for the same result).
- `build` vs `build-hard` vs `feature`/`feature-argon`: clear spec on a few files -> `build`; many edge cases/complex files or retry -> `build-hard` (Neon medium); only use `feature` (Orchestrator Neon) or `feature-argon` (Orchestrator Argon) when agy should plan the split itself.
- Neon vs Argon (`feature`/`think` vs `feature-argon`/`think-argon`): pick Neon by default for the highest coding benchmarks (`65.2%` Terminal-Bench 4.1); pick Argon for long-document/domain analysis, or when consulting both models for a second opinion on critical architecture. If one family is blocked, the tier's fallbacks move to the other automatically.
- Without `@model` the watcher picks only `quick` (short read-only) or `build` (changes files). It never picks a higher tier.
- 3.8 Flash is only the last fallback when the Gemini 4 models are blocked; a result from it starts with an `[알림]` line. Review it more carefully.

If the user asks to delegate and the job belongs on the "keep" side, say so in one line and offer to do it directly; follow the user's choice. agy has no web search. Never trust factual claims from agy without checking.

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

- **`Orchestrator` vs `/swarm` vs `/run-workflow`**: daily multi-file feature in one flow -> `feature`/`feature-argon`; independent non-overlapping file edits needing cross-verification -> `@cmd: swarm`; mechanical N-item fan-out or strict sequential schema stages -> `@cmd: run-workflow`. Prefer several `-NoWait` `build` tasks when you already wrote exact per-file specs.
- **Interactive TUI commands & consumer-plan note**: `/teamwork`, `/grill-me`, `/rewind`, `/fork`, `/btw`, `/compact`, `/learn`, `/permissions`, `/tasks`, `/agents`, `/resume` are **interactive-TUI only** (rejected by headless watcher and `agy-brief-lint`). Also, Antigravity consumer plans (Google AI Pro/Ultra) officially scope `agy -p` to direct scripting rather than third-party agent wrapping — for multi-milestone `/teamwork`, interactive `/grill-me`, or when you prefer direct execution, write a clean spec `.md` file and let the user run `@spec.md` interactively in their own `agy` session.

## 2. Consult Neon (`think`) or Argon (`think-argon`) before very complex decisions

For a design across several modules, a structural change that is hard to undo, a bug whose cause you cannot see, or a decision between two or more directions that is hard to call: consult `think` (Neon high) or `think-argon` (Argon high) at least once before you decide. Use the `samjil-handoff` channel (default `think`; set `위임모델: think-argon` in message front-matter to route to Argon or run a cross-model second opinion).

- Send: the problem, the options, your recommendation and why, **the relevant file paths and the constraints** (the reviewer does not know this conversation), and always: "Do not simply agree. Focus on objections, missed edge cases and alternatives; list what you would change as numbered items."
- One round trip as a rule (two at most, e.g., when getting both Neon and Argon perspectives on a critical architectural call). These do not count toward the 3-call budget of a delegation.
- If the consultation fails or passes the 20-minute limit, do not ask again: decide alone and tell the user you could not consult.
- After deciding, tell the user in one or two lines what you changed because of the consultation, and in one line each what you did not take and why. The decision and the responsibility stay with you.
- Hard bug: `think`/`think-argon` finds the cause and the fix direction; `deep` (or `@cmd: boost` on `deep`/`think`) makes the fix.

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
   - `DEAD`: start the watcher first (`ensure-agy-running.ps1 -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0`). `MANUAL_STOP` means the user stopped it on purpose: ask before starting, or do the job yourself. Details: `references/watcher.md`.
   - Leave out `@cwd` for tasks that need no files. For tasks that read or write project files, confirm the project folder with the user once per conversation and say that agy runs with permissions skipped inside it (suggest it be under git). Never guess a folder. Before a large edit, save `git diff` somewhere first.
2. **Call 2: read the result and check it in one command**: the `-Poll` output, `git diff --stat` (and the diff you need to read) and the key test command, together in one shell call.
3. **Call 3 (only if needed): fix the remainder yourself.**

**Wait limit = the tier's limit.** If the task is not done by then, the `-CancelOnTimeout` poll cancels it (`===CANCELLED=== <ID>`, exit 4): do the job yourself. Do not poll in a loop. To cancel earlier: `submit-task.ps1 -Cancel <ID>`.

**Escalate once, one step.** If the result fails its tests: `build` -> `build-hard`, `build-hard` -> `deep`, sent once (same brief plus what failed). The two waits together stay under 20 minutes when you started at `build`, 30 minutes when you started at `build-hard`. A failed `deep`, `quick`, `feature` or `think` task is not re-sent: fix it yourself (consult `think` first if the cause is unclear). If agy fails (`===ERROR===`, or the answer reports an agy run failure), check `git diff --stat` for half-done edits and finish directly.

**Large context.** When the context is over the limit (200k; `AGY_CTX_SUBAGENT_THRESHOLD` changes it), the prompt hook adds `[컨텍스트 <N>k] ...` before you start. If that question ends up delegated, write the brief yourself and give it to one fresh-context subagent running a cheap model, which submits, waits, reviews the diff and runs the tests; you only read its report (at most 5 lines: passed or not, changed files, concerns) and do a final `git diff --stat`. If you only see the warning from `submit-task.ps1` after submitting, the task is already queued: do not start your own poll; hand the task ID and the test command to such a subagent for the wait and the review.

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
