# Changelog

All notable changes to MoonPot are documented here.

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
