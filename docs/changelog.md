# Changelog

All notable changes to MoonPot are documented here.

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
