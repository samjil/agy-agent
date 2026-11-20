# Model tiers

Write `@model: <tier>` in the directive lines. The tiers, their models, fallbacks and wait limits live in `~/.samjil/delegate-agy/config/models.json` (repository: `runtime/delegate-agy/config/models.json`). Hydrogen is the fast execution family (`quick`/`build`), **Neon** leads coding/reasoning benchmarks, and **Argon** is strong at long-document/domain and second-opinion review (`feature-argon`/`think-argon`). Both Neon and Argon are first-class tiers with cross-family fallbacks; 3.8 Flash is only the last fallback; Claude and GPT-OSS models are not used.

| Tier | When | Model, then fallbacks (quota/overload errors only) | Wait limit |
|---|---|---|---|
| `quick` | lookups, summaries, translation, format conversion, short questions | hydrogen-low -> hydrogen-medium -> neon-low -> 3.8-flash-low | 3 min |
| `build` | clearly specified implementation, a few files, tests, repeated edits | hydrogen-medium -> hydrogen-high -> neon-low -> 3.8-flash-medium | 8 min |
| `build-hard` | `build` with many edge cases or complex multi-file edits, or a `build` that failed once | neon-medium -> hydrogen-high -> neon-high -> argon-medium -> 3.8-flash-medium | 12 min |
| `feature` | multi-file feature where agy also plans the split and the steps (Neon plans/reviews + Hydrogen executes) | orchestrator-neon -> neon-high -> orchestrator -> hydrogen-high -> 3.8-flash-medium | 20 min |
| `feature-argon` | same multi-file orchestration using Argon planning + Hydrogen execution | orchestrator -> argon-high -> orchestrator-neon -> hydrogen-high -> 3.8-flash-medium | 20 min |
| `think` | design review, root cause of a hard bug, consultation (handoff default; coding/reasoning priority) | neon-high -> argon-high -> neon-medium -> argon-medium -> hydrogen-high | 20 min |
| `think-argon` | design review, cross-model second opinion, long-document/domain analysis | argon-high -> argon-medium -> neon-high -> hydrogen-high | 20 min |
| `deep` | extreme logic in few files (algorithms, concurrency, parsers/state machines, numeric precision, performance targets), fixing a bug whose cause `think`/`think-argon` found, failed `build-hard` re-sent | neon-xhigh (Extra) -> neon-high -> hydrogen-xhigh -> argon-high -> 3.8-flash-medium | 20 min |

Full model IDs: `gemini-4-hydrogen-low|medium|high|xhigh`, `gemini-4-neon-low|medium|high|xhigh`, `gemini-4-argon-low|medium|high`, `gemini-pro-orchestrator-neon`, `gemini-pro-orchestrator-g1-pro`, `gemini-3.8-flash-low|medium`.

- Benchmarks (2026-11-17 measured + 2026-11-18 Artificial Analysis v5 / Google DeepMind):
  - Artificial Analysis Intelligence Index: Hydrogen (`low` 27, `medium` 41, `high` 51, `xhigh` 54), Argon (`high` ~50–53, Deep SWE v1.1 77.9%), **Neon (`low` 44, `medium` 55, `high` 60, `xhigh` 61.4)**.
  - Agentic coding: `gemini-4-neon-xhigh` ranks #1 on AA Coding Agent Index (58.6); `neon-high` hits 65.2% on Terminal-Bench 4.1, 65.4% on CursorBench 4.1, 46.2% on FrontierCode 2.0 (surpassing Argon's ~57.4% Terminal-Bench 4.0 and 53.2 Coding Agent).
  - Speed & cost: Hydrogen ($1.50/$7.50 per 1M tokens; finished a 4-file feature in 93 s) stays default for `quick`/`build`; Neon ($3/$15, 25% cheaper than Argon $4/$20, ~3x faster than flagship). `Orchestrator (Neon)` cuts quota burn by ~24% and completion time by ~19% vs standalone planning models.
- Without `@model`: the watcher picks `quick` (short, read-only) or `build` (changes files, analysis, long). `AGY_AUTO_MODEL=off` turns this off (`build`).
- A model name instead of a tier (`@model: gemini-4-neon-high`) uses exactly that model with no fallback; when it is blocked the task fails. Old aliases still work: `low` = `quick`, `medium` = `build`, `high` = `build-hard`.
- A value that is neither a tier nor an allowed model fails before agy is called; fix it and resend.
- The watcher runs `agy models` once at start (20 s limit). Models missing from the account are skipped (the tier continues with its next model) and logged in `watcher.log`.
- A 3.8 Flash result after the Gemini 4 models were blocked starts with an `[알림]` line, and the viewer shows a `3.8 대체` badge.
- Escalate a failed task once, one step: `build` -> `build-hard` -> `deep`. A failed `deep` is fixed by Claude.
- A running `@session` keeps its starting model; asking for another model without `@upgrade` returns an error and keeps the conversation safe. For a tier, any model in the tier's chain counts as the same.
- Change tiers for one PC in `models.local.json` next to `models.json`: only the tiers and fields you write are replaced (for example `{ "tiers": { "build": { "wait_sec": 600 } } }`). Updates overwrite `models.json`, never `models.local.json`.
