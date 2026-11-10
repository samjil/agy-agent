---
name: samjil-delegate-agy
description: "Delegate coding and routine tasks to the Antigravity CLI (agy) through a local watcher to save Claude quota. Claude keeps the design and the hardest part and reviews every result. Use when the user says 'delegate', 'ask agy', 'let agy do it', 'save quota', or turns delegate mode on. Windows only; needs a one-time local runtime install (see Setup)."
license: MIT
compatibility: "Windows 10/11 with Windows PowerShell 5.1, Claude Code, and the Antigravity CLI (agy) installed and signed in."
metadata:
  version: "1.0.0"
  homepage: "https://github.com/samjil/agy-agent"
---

# samjil-delegate-agy

Send the cheap-to-verify parts of a job to the Antigravity CLI (`agy`), keep the thinking for Claude, and review everything that comes back. Goal: spend less Claude quota without lowering quality.

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

## 1. When to delegate

- **On request (always applies):** delegate when the user asks ("ask agy", "delegate this", "use agy for the rest") or says delegate mode is on for this conversation.
- **Always-on (the default install):** if the session start context contains `[samjil-delegate-agy]`, the installer registered the session hook: delegate by default for every task. If that context is missing, the user installed with `-AlwaysOff`: delegate only on request.

## 2. Who does what

| Claude does it directly | agy does it |
|---|---|
| Design, architecture, trade-offs, unclear requirements | Implementation after the design is fixed |
| The single hardest piece of a task | Normal bug fixes, refactors, tests |
| Security, auth, payments, migrations, anything hard to undo | UI built from a written spec, docs, translation, cleanup |
| Needs Claude-only tools (web search, browser, MCP, documents) | Scripts, format conversion, log reading, first-pass review |
| Trivial: a one-line edit is cheaper than writing a brief | |

Split big jobs: you design and take the hardest piece, agy gets the rest with the spec. If unsure, delegate and review strictly. If the same problem fails review three times, take that piece yourself.

agy has no web search. Never trust factual claims from agy without checking.

## 3. Delegate in four steps (plus retry on failure)

1. **Watcher.** Check it is running; start it if not (hidden, no window):
   ```bash
   S="$USERPROFILE/.samjil/delegate-agy/scripts/sub"
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/ensure-agy-running.ps1" -CheckOnly -StaleThresholdSeconds 0   # prints ALIVE | DEAD | MANUAL_STOP
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$S/ensure-agy-running.ps1" -ConfirmDelaySeconds 0 -StaleThresholdSeconds 0   # starts it
   ```
   `MANUAL_STOP` means the user stopped it on purpose: ask before starting. Details: `references/watcher.md`.
2. **Folder.** For tasks that read or write project files, confirm the project folder with the user once per conversation, and say that agy runs with permissions skipped inside it (suggest it be under git). Never guess a folder.
3. **Brief.** Write the instruction (template below) and submit it:
   ```bash
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/submit-task.ps1" <<'CLAUDE_TASK_EOF'
   @cwd: C:\path\to\project
   @model: gemini-3.8-flash-medium
   [1. Goal] one or two lines; say whether it is read-only or edits files
   [2. Spec] file paths (with line numbers), exact AS-IS -> TO-BE, names and values. Do not paste whole files
   [3. Limits] rules that matter for this task, files not to touch. If something is unclear: write [NEED INFO] and a question as the first line of the answer and do not touch that part
   [4. Verify and report] the test/build command; reply as: status, changed files, one-line test result, concerns
   CLAUDE_TASK_EOF
   ```
   Leave out the `@cwd` line for tasks that need no files (translation, writing).
4. **Wait.** The script waits about 170 s. If it prints `===PENDING=== <ID>`, the task is still running: do not resubmit, call `submit-task.ps1 -Poll <ID>` (a `high` model takes about 10 minutes). Output `===RESULT===` means an answer exists (read it, failures can arrive as the answer text); `===ERROR===` means no answer.
5. **If agy fails** (`===ERROR===`, or the answer reports an agy run failure such as an interrupted stream): check `git diff --stat` for half-done edits, then resend the same brief with "continue from the current files" **1-2 more times when delegating still clearly pays**: the delegate estimate is more than 20% below direct and the run is short (low/medium, or a high run not already past ~10 minutes). If the saving is small or the run takes too long, finish that piece directly. Do not re-record the estimate (it is fixed at decision time); add `(agy failed, retried N times)` or `(agy failed, finished directly)` to the closing line.

More: several tasks at once (`-NoWait`, then `-Poll <ID1>,<ID2>`, at most 5 at a time), `@session`, `@model`, `@upgrade`: `references/brief-and-commands.md` and `references/models.md`.

## 4. Always review what agy returns

Never pass agy output on unchecked. Bar: "as good as if Claude had done it".

- Requirements and spec all met? Nothing invented, nothing skipped?
- Code: read the diff yourself and re-run the key test or build. Do not trust "tests passed" in the report.
- agy must not commit. The watcher warns at the top of the answer if git state changed. You review the diff and you decide on the commit.
- Facts and numbers: check them or leave them out.
- Not good enough: resubmit with concrete feedback (use `@session: <name>` to continue; raise the model one step: low, medium, high).
- Do not touch the same repository while agy is working in it.

## 5. Say what happened

End the answer with one line that starts with a bold tag, so the reader sees at a glance who did the work. Put the same tag on the classification line you write before the work and on the result line after it, so every delegation-related line is easy to spot. Bold only the tag, the key words of the reason and the token numbers; leave the rest plain. No colors, emoji or headings. Write numbers like `3.5k`.
- Delegated: `**[Agy delegation]** agy (gemini-3.8-flash-medium) did the work and Claude **reviewed** it.` Add `(re-delegated twice, fixed part myself)` when that happened.
- Done directly: `**[Agy delegation · direct]** Why: <plain reason>`, for example `**[Agy delegation · direct]** Why: it is **design** work` or `**[Agy delegation · direct]** Why: **too small** to delegate, **3.5k** tokens direct vs **5k** delegated (estimate)`.

Include level in closing tags: e.g. `**[Agy delegation · level low]**`, Korean `**[Agy 위임 · 수준 낮음]**`, `**[Agy 위임 · 직접 처리 · 수준 보통]**`. Decide the level before starting by looking at the prompt using these criteria (never by feel):
- `low` / `낮음`: explanation/verification only or editing only one place.
- `medium` / `보통`: editing 1–3 files and simple tests.
- `high` / `높음`: root cause investigation, multi-file design, modifying UI/server/tests together.
If the session-start line `[수준별 예상]` has a formula for that level, plug the call count into that formula; if samples are insufficient, use the overall formula. The sample threshold is not fixed: a bootstrap of the current samples checks that the median per-call value lands within ±15% with 95% probability (30 to 1000 samples, no distribution assumed).

Separators: `vs` inside a pair (direct vs delegate), and ` | ` between the token pair and the time pair, never `·`. Write it on two lines: the tag and the content first, then the estimate on a new line (end the first line with two spaces so it renders as a line break; no blank line). Both lines carry the token estimate in this exact shape, so it can be compared with the real usage automatically: `Estimated tokens: direct **X** vs delegate **Y**` (Korean: `예상 토큰: 직접 **X** vs 위임 **Y**`). Get X and Y by counting the tool calls you expect to make, not by feel: direct = files to read + files to edit + checks to run + 1, delegate = 1 submit + 0-2 result checks + the review calls. Convert calls to tokens with the `[토큰 예상]` line from the session-start hook (a + b x calls, refreshed from measured usage). If that line is missing, use direct = 0.8k + 1.3k x calls and delegate = 2.5k + 1.0k x calls. Pick the cheaper path; if they are within 20 percent, delegate. (Note: on delegated turns, tool calls unrelated to delegation—such as separate exploration or unrelated edits—are automatically excluded from the measured delegation cost `d_related` and calls `calls_related`, including up to 3 review calls immediately following the result.)

Also estimate time and write it on the same line: `Estimated time: direct **A** vs delegate **B**` (Korean: `예상 시간: 직접 **A** vs 위임 **B**`, like `45초`, `3분`, `1시간 20분`). Defaults measured on the author's PC: direct = 11 s + 15 s x calls; delegate = 15 s x your calls + the agy run time (low about 15 s, medium about 1 min, high about 7 min) + waiting for earlier jobs of the same session. Cost in tokens decides; time is reported, and decides only when the user is in a hurry.

Estimates come from data, never from feel. Count the calls first, then put the count into the formulas on the session-start lines (`[토큰 예상]`, `[시간 예상]`; they hold the latest measured numbers). The defaults above are used only when those lines are missing. This holds on a new PC with few samples too: a rough estimate from little data is still right, because the formulas sharpen as samples accumulate (the statistics refit on recent data). Write the estimate from the call count you counted before the work, and do not rewrite it afterwards with what you learned while working.

Collecting mode: when the session-start line says `수집 모드: 위임 표본 N/20` (a new PC, or fewer than 20 measured delegations), skip the cost comparison and delegate everything delegable, so the statistics can build up. Rules 1-4 for working directly (needs this conversation, design or hardest part, costly if wrong, Claude-only tools) still apply. Very small jobs (one expected tool call or fewer) are still done directly in this mode. Add `(collecting statistics, N/20)` to the closing line when you delegated for this reason. The mode ends by itself at 20 measured delegations.

When you answer in Korean, use the Korean tags and the plain-language reasons in `references/full-rules-ko.md` (`**[Agy 위임]**`, `**[Agy 위임 · 직접 처리]** 이유: ...`).

## 6. Switch off, remove, more

- Stop the watcher: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.samjil/delegate-agy/scripts/stop-agy.ps1"`.
- Remove the skills, tools and the always-on hook: run `uninstall.ps1` from the same repository (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/samjil/agy-agent/main/uninstall.ps1 | iex"` or the local file). Task history under `~/.samjil` is kept; delete it by hand to remove that too.
- Dashboard of delegated tasks: `http://127.0.0.1:8787` (start it with `viewer/ensure-viewer-running.ps1` under `~/.samjil`).
- Troubleshooting, logs, stuck tasks: `references/watcher.md`.
- The author's complete original rules (Korean, long): `references/full-rules-ko.md`. Read only when a case above does not cover it.
