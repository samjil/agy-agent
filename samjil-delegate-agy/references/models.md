# Model tiers

Write `@model: <tier>` in the directive lines. The tiers, their models, fallbacks and wait limits live in `~/.samjil/delegate-agy/config/models.json` (repository: `runtime/delegate-agy/config/models.json`). Hydrogen is the default family; 3.8 Flash is only the last fallback; Claude and GPT-OSS models are not used.

| Tier | When | Model, then fallbacks (quota/overload errors only) | Wait limit |
|---|---|---|---|
| `quick` | lookups, summaries, translation, format conversion, short questions | hydrogen-low -> hydrogen-medium -> 3.8-flash-low | 3 min |
| `build` | clearly specified implementation, a few files, tests, repeated edits | hydrogen-medium -> hydrogen-high -> 3.8-flash-medium | 8 min |
| `build-hard` | `build` with many edge cases, or a `build` that failed once | hydrogen-high -> argon-medium -> 3.8-flash-medium | 12 min |
| `feature` | multi-file feature where agy also plans the split and the steps | orchestrator -> hydrogen-high -> argon-medium -> 3.8-flash-medium | 20 min |
| `think` | design review, root cause of a hard bug, consultation (handoff default) | argon-high -> argon-medium -> hydrogen-high | 20 min |
| `deep` | hard logic in few files (algorithms, concurrency, parsers/state machines, numeric precision, performance targets), the fix after Argon found a cause, a failed `build-hard` re-sent | hydrogen-xhigh (Extra) -> argon-high -> hydrogen-high -> 3.8-flash-medium | 20 min |

Full model IDs: `gemini-4-hydrogen-low|medium|high|xhigh`, `gemini-4-argon-low|medium|high`, `gemini-pro-orchestrator-g1-pro`, `gemini-3.8-flash-low|medium`.

- Measured 2026-11-17 (one run each, test tasks with hidden tests): 4-file feature: Hydrogen medium 93 s, high 142 s, Argon medium 190 s, Orchestrator 247 s, Extra 299 s, Argon high 412 s, 3.8 Flash medium 562 s, all 17/17. Argon low got 2/4 on an easy task, so it is not in any tier.
- Without `@model`: the watcher picks `quick` (short, read-only) or `build` (changes files, analysis, long). `AGY_AUTO_MODEL=off` turns this off (`build`).
- A model name instead of a tier (`@model: gemini-4-argon-high`) uses exactly that model with no fallback; when it is blocked the task fails. Old aliases still work: `low` = `quick`, `medium` = `build`, `high` = `build-hard`.
- A value that is neither a tier nor an allowed model fails before agy is called; fix it and resend.
- The watcher runs `agy models` once at start (20 s limit). Models missing from the account are skipped (the tier continues with its next model) and logged in `watcher.log`.
- A 3.8 Flash result after the Gemini 4 models were blocked starts with an `[알림]` line, and the viewer shows a `3.8 대체` badge.
- Escalate a failed task once, one step: `build` -> `build-hard` -> `deep`. A failed `deep` is fixed by Claude.
- A running `@session` keeps its starting model; asking for another model without `@upgrade` returns an error and keeps the conversation safe. For a tier, any model in the tier's chain counts as the same.
- Change tiers for one PC in `models.local.json` next to `models.json`: only the tiers and fields you write are replaced (for example `{ "tiers": { "build": { "wait_sec": 600 } } }`). Updates overwrite `models.json`, never `models.local.json`.
