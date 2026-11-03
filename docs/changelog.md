# Changelog

All notable changes to MoonPot are documented here.

## [0.2.0] — 2026-11-16

### Added (v0.2 completion — provider + streaming)

- **`OpenAiCompatProvider`** (`ai/openai.mbt`) — an OpenAI-compatible
  `AiProvider` implementation. `build_request` produces a standards-compliant
  `/v1/chat/completions` payload (system + user messages, `json_object`
  response format, `Bearer` auth); `make(base_url, api_key, model)` defaults
  to the OpenAI endpoint / `gpt-4o-mini` and is `enabled` iff a key is supplied.
  The live HTTP call (via `@crescent.fetch`) lives in the server; without a key
  the provider degrades to a deterministic offline design so the pipeline never
  breaks.
- **Provider-aware `/api/generate`** — when `MOONPOT_AI_KEY` (and optionally
  `MOONPOT_AI_BASE_URL` / `MOONPOT_AI_MODEL`) is set, the route calls the
  OpenAI-compatible endpoint live and maps the response back into a design tree;
  any network / parse / shape error self-heals to `MockProvider` (consistent
  with the v0.2 structured-output contract).
- **Streaming generate over WebSocket** — new `WS /ws/gen` endpoint streams
  `start` → `progress` (with shape count) → `done` (project + notes) frames.
  True Server-Sent Events are **not** supported by this crescent build because
  `HttpResponse` is fully buffered, so progressive generation is delivered over
  WS instead (documented limitation, not a regression).

### Changed

- `server` adds `bobzhang/crescent/fetch` and `moonbitlang/core/env` deps;
  service `InfoBody` version bumped to `0.2.0`.
- `OpenAiCompatProvider` uses `pub impl AiProvider` and exposes `build_request`
  so the request shape is testable fully offline (no network, no env).

### Quality gate

- `moon build` 0 warnings / 0 errors; selftest **24 blocks** all green;
  `e2e/run_e2e.sh` **PASS=25 FAIL=0** (added `/ws/gen` streaming channel).

## [0.1.2] — 2026-11-03

### Added (v0.2 iteration start — AI upgrade)

- **KB upgrade** — TF → **TF-IDF** with smooth IDF weighting (single-doc KBs
  degrade to pure TF, no zero-vector degeneration); **CJK bigram** tokenization
  (e.g. `世界` → `世`,`界`,`世界`) for higher retrieval precision.
- **Provider contract suite** — `ai.provider_contract[T]` runs one shared set
  of assertions (determinism, JSON round-trip, shape bounds, non-empty notes)
  against **any** `AiProvider`; the selftest exercises it on both `MockProvider`
  and a local `FakeProvider`.
- **Structured-output contract + self-heal** — `ai.validate_design` checks a
  generated tree is renderable; `ai.generate_safe` falls back to `MockProvider`
  when a provider returns malformed output, so the pipeline never breaks. Wired
  into `server`, `mcp` and `cli`.
- **KB tests** — IDF discrimination, CJK bigram emission, incremental `add()`
  order preservation.

### Changed

- `MockProvider`'s `impl AiProvider` is now `pub impl` so the generic
  `generate_safe`/`provider_contract` can be instantiated with it cross-package.
- `mcp` `list_projects` response uses `Json(arr)` instead of the deprecated
  `Array::to_json`.

### Quality gate

- `moon build` 0 warnings / 0 errors; selftest **22 blocks** all green;
  `e2e/run_e2e.sh` **PASS=24 FAIL=0**.

## [0.1.1] — 2026-10-16

### Added

- **Test suite expansion** — `cmd/selftest` grew from 12 to 20 blocks covering: AI boundary inputs (empty / all-keyword / tiny canvas) and generation determinism; a local `FakeProvider` proving `AiProvider` is swappable; corrupted-snapshot resilience (`load_from` returns `Err`, CLI recovers with a fresh store); full MCP method matrix with JSON-RPC error codes (`-32600`/`-32601`/`-32700`/`-32001`/`-32002`); KB edge cases (empty index, `topk` 0/overflow, CJK queries, `add()`); CLI error paths and help variants; 500-shape + Unicode + deep-nesting snapshot round-trips; HTML escaping; and a full generate → auto-color → flatten → tag-all → normalize-names pipeline.
- **End-to-end suite** — `e2e/run_e2e.sh` + `e2e/ws_client.mjs`: boots the HTTP server, asserts all 9 REST endpoints plus 404/400 error bodies, performs a WebSocket JSON-RPC round-trip via Node ≥ 22 native WebSocket, exercises the MCP file-transport server and the CLI full chain (init → new-project → generate → run-skill → persisted snapshot → RAG ask → bad subcommand), and re-runs the selftest suite. Summary gate: `PASS=n FAIL=0`.
- **`ai.gen_result` factory** — lets external packages construct `GenResult` (struct literals are not constructible cross-package).
- **Long-term plan** — `docs/long-term-plan.md`: staged roadmap v0.2 → v1.0 with acceptance criteria, risk register and quality gates.

### Changed

- `AiProvider` is now a `pub(open)` trait, so external packages can implement their own providers.

### Fixed

- **Tiny-canvas crash** — a generation request whose content area computed non-positive (width/height too small) made `grid_cells` return an empty array, then `cells[i]` indexed out of bounds and aborted. The content area is now clamped to ≥ 64px in both dimensions.

## [0.1.0] — 2026-10-16

MVP for the MoonBit 2026 October Hackathon ("AI Application" track).

### Added

- **P1 `common`** — domain model (Project / File / Page / Shape / Color / ShapeKind) with JSON round-trip (`ToJson`/`FromJson`) and cross-package record-update helpers.
- **P2 `store`** — `Store` abstraction: in-memory state + JSON file snapshot (`save_as` / `load_from`), project & file CRUD.
- **P3 `ai`** — `AiProvider` trait, deterministic offline `MockProvider` (keyword-driven prompt → design tree) and standalone HTML/CSS renderer.
- **P4 `skill`** — design-tree transformer registry: `flatten`, `auto-color`, `tag-all`, `normalize-names`.
- **P5 `kb`** — bilingual (EN + CJK) tokenizer, TF bag-of-words embedding, cosine similarity retrieval, RAG context builder.
- **P6 `mcp`** — JSON-RPC 2.0 dispatcher: `moonpot/list_projects`, `moonpot/read_file`, `moonpot/generate_design`, `moonpot/run_skill`, `moonpot/query_kb`; file-transport server executable (`cmd/mcpserver`).
- **P7 `cli`** — native CLI (`cmd/cli`) with `init`, `new-project`, `generate`, `run-skill`, `ask`, `mcp`, `help` and a global `--store` flag.
- **P8 `server`** — crescent HTTP server: 9 REST endpoints, `POST /api/rpc` (MCP-over-HTTP passthrough), `/ws` WebSocket bridge to the MCP dispatcher.
- **Selftest** — `cmd/selftest` executable covering all modules end-to-end (12 blocks, all green).
