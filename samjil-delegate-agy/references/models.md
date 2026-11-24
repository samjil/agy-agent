# Model tiers

Write `@model: <tier>` in the directive lines. The tiers, their models, fallbacks and wait limits live in `~/.samjil/delegate-agy/config/models.json` (repository: `runtime/delegate-agy/config/models.json`). All Gemini models share one "Gemini Models" quota. **Neon** is the balanced main model (80%+ of real development), **Hydrogen** handles fast boilerplate/tests/simple UI/summaries, and **Carbon** is reserved for architecture/initial design, unexplained multi-service bugs, hard legacy logic, final review before big changes, or problems Neon could not solve. Claude and GPT-OSS models are not used.

| Tier | When | Model, then fallbacks (quota/overload errors; or effort-related HTTP 400 on `-xhigh`) | Wait limit |
|---|---|---|---|
| `quick` | lookups, summaries, translation, format conversion, short questions (fastest, lowest quota) | hydrogen-low -> hydrogen-medium -> neon-low | 3 min |
| `build` | boilerplate, unit tests, simple UI, clearly specified repeated edits (50%+ less quota than Carbon) | hydrogen-medium -> hydrogen-high -> neon-low | 8 min |
| `build-hard` | multi-file edits, refactors, debugging, many edge cases, or failed `build` (~30% less quota than Carbon) | neon-medium -> neon-high -> hydrogen-xhigh -> carbon-medium | 12 min |
| `feature` | multi-file feature where agy also plans the split and the steps (Neon plans/reviews + Hydrogen executes) | orchestrator-neon -> neon-high -> orchestrator-carbon -> hydrogen-high | 20 min |
| `feature-carbon` | hard architecture/initial design across multiple files (Carbon reads/designs read-only + Hydrogen executes; ~24% less quota and ~19% faster than Carbon alone) | orchestrator-carbon -> carbon-high -> orchestrator-neon -> neon-high | 20 min |
| `think` | design review, root cause of a hard bug, consultation (handoff default; Neon) | neon-high -> neon-medium -> carbon-high -> hydrogen-high | 20 min |
| `think-carbon` | architecture/initial design, unexplained multi-service bug, hard legacy logic, final review before big changes — problems Neon could not solve (heaviest quota) | carbon-high -> carbon-medium -> neon-high -> neon-xhigh | 20 min |
| `deep` | extreme logic in few files (algorithms, concurrency, parsers/state machines, numeric precision, performance targets), fixing a bug whose cause `think`/`think-carbon` found, failed `build-hard` re-sent | neon-xhigh (Extra) -> neon-high -> carbon-high -> hydrogen-xhigh | 20 min |

Full model IDs: `gemini-4-hydrogen-low|medium|high|xhigh`, `gemini-4-neon-low|medium|high|xhigh`, `gemini-4-carbon-low|medium|high`, `gemini-pro-orchestrator-neon`, `gemini-pro-orchestrator` (Orchestrator Carbon).

- Model facts & quota cost (single shared Gemini Models quota; Carbon = 100% baseline):
  - **Carbon** (`gemini-4-carbon-low|medium|high`): flagship, deepest thinking. AA Intelligence 60 (high); ~56 tok/s, first token ~73 s (high). Heaviest quota cost (100% baseline; API $4/$20).
  - **Neon** (`gemini-4-neon-low|medium|high|xhigh`): balanced main model for 80%+ of development. AA Intelligence 60 (high) / 61 (xhigh); AA Coding Agent Index #1 at 58.64 (xhigh). ~101–110 tok/s, first token ~41 s. ~30–32% less quota than Carbon ($3/$15). Note: `xhigh` may return HTTP 400 on some accounts; the watcher then falls back to `neon-high`.
  - **Hydrogen** (`gemini-4-hydrogen-low|medium|high|xhigh`): fast model for boilerplate, unit tests, simple UI, summaries, clear repetitive work. AA Intelligence 51 (high) / 54 (xhigh); ~165–170 tok/s, first token ~20 s. 50%+ less quota than Carbon ($1.50/$7.50).
  - **Orchestrators**: `gemini-pro-orchestrator-neon` (Neon plans/reviews + Hydrogen executes) and `gemini-pro-orchestrator` (Carbon reads dependencies and designs read-only + Hydrogen implements; ~24% less quota and ~19% faster than Carbon alone). The executor is always Hydrogen.
- Without `@model`: the watcher picks `quick` (short, read-only) or `build` (changes files, analysis, long). `AGY_AUTO_MODEL=off` turns this off (`build`).
- A model name instead of a tier (`@model: gemini-4-neon-high`) uses exactly that model with no fallback; when it is blocked the task fails. Old aliases still work: `low` = `quick`, `medium` = `build`, `high` = `build-hard`, `think-argon` = `think-carbon`, `feature-argon` = `feature-carbon`.
- A value that is neither a tier nor an allowed model fails before agy is called; fix it and resend.
- The watcher runs `agy models` once at start (20 s limit). Models missing from the account are skipped (the tier continues with its next model) and logged in `watcher.log`.
- Escalate a failed task once, one step: `build` -> `build-hard` -> `deep`. A failed `deep` is fixed by Claude.
- A running `@session` keeps its starting model; asking for another model without `@upgrade` returns an error and keeps the conversation safe. For a tier, any model in the tier's chain counts as the same.
- Change tiers for one PC in `models.local.json` next to `models.json`: only the tiers and fields you write are replaced (for example `{ "tiers": { "build": { "wait_sec": 600 } } }`). Updates overwrite `models.json`, never `models.local.json`.
