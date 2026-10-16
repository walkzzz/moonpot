# walkzzz/moonpot

**Penpot ported to MoonBit** — an open-source design & prototyping platform backend, rebuilt natively in MoonBit with five AI-era modules built in from day one: **AI generation, Skill transformers, MCP server, CLI, and a KB (RAG) engine**.

> MoonBit 2026 October Hackathon entry — **"AI Application" track**.

## Why MoonPot

Penpot proved that open-source design tooling matters. MoonPot re-imagines its backend in MoonBit:

- **Zero external dependencies** — in-memory store + JSON file snapshots behind a `Store` trait. PostgreSQL/Redis can be swapped in later without touching callers.
- **AI-native** — deterministic offline AI generation (mock provider, swappable), a skill subsystem for design-tree transformers, and a bilingual (English + CJK) TF-cosine knowledge base for RAG retrieval.
- **Three transports, one core** — the same operations are exposed as a REST API, an MCP JSON-RPC dispatcher (over stdio-file, HTTP, and WebSocket), and a native CLI.

## Modules

| Module | Path | What it does |
| --- | --- | --- |
| `common` | `common/` | Domain model: projects, files, pages, shapes, colors (JSON round-trippable) |
| `store` | `store/` | `Store` abstraction: in-memory + JSON file snapshot persistence |
| `ai` | `ai/` | Prompt → design tree generation (keyword-driven mock provider) + HTML/CSS renderer |
| `skill` | `skill/` | Design-tree transformers: `flatten`, `auto-color`, `tag-all`, `normalize-names` |
| `kb` | `kb/` | Bilingual tokenizer, bag-of-words embedding, cosine retrieval, RAG context |
| `mcp` | `mcp/` | JSON-RPC 2.0 dispatcher (`moonpot/list_projects`, `moonpot/read_file`, `moonpot/generate_design`, `moonpot/run_skill`, `moonpot/query_kb`) |
| `cli` | `cli/` | Native CLI: `init`, `new-project`, `generate`, `run-skill`, `ask`, `mcp`, `help` |
| `server` | `server/` | crescent REST API (9 endpoints) + MCP-over-HTTP (`POST /api/rpc`) + WebSocket bridge (`/ws`) |

## Build & Run

```bash
moon build          # 0 warnings, 0 errors
```

### Self-test (all modules)

```bash
moonrun _build/wasm/debug/build/cmd/selftest/selftest.wasm
# ALL STORE + AI + SKILL + KB + MCP + CLI TESTS PASSED
```

### CLI

```bash
moonrun _build/wasm/debug/build/cmd/cli/cli.wasm help
moonrun _build/wasm/debug/build/cmd/cli/cli.wasm init --store ./demo.json
moonrun _build/wasm/debug/build/cmd/cli/cli.wasm generate "landing page with 3 cards" --name Landing --store ./demo.json
moonrun _build/wasm/debug/build/cmd/cli/cli.wasm run-skill proj_gen_Landing f1 flatten --store ./demo.json
moonrun _build/wasm/debug/build/cmd/cli/cli.wasm ask "MoonBit extern C" --docs-file docs.json
```

### MCP server (file transport)

```bash
# one JSON-RPC request per line in ./mcp_in.jsonl, or omit the file for a built-in demo
moonrun _build/wasm/debug/build/cmd/mcpserver/mcpserver.wasm
```

### HTTP server (REST + WebSocket)

```bash
moonrun _build/wasm/debug/build/server/server.wasm
# moonpot server listening on http://0.0.0.0:4000
```

| Method | Path | Description |
| --- | --- | --- |
| GET | `/` | Service info + endpoint list |
| GET | `/health` | Liveness probe |
| GET | `/api/projects` | List projects |
| GET | `/api/projects/:pid/files/:fid` | Read a design file |
| GET | `/api/skills` | List available skills |
| POST | `/api/generate` | Prompt → design tree (stored) |
| POST | `/api/projects/:pid/files/:fid/skills/:name` | Apply a skill to a stored file |
| POST | `/api/kb/query` | RAG retrieval over KB documents |
| POST | `/api/rpc` | JSON-RPC 2.0 passthrough to the MCP dispatcher |
| WS | `/ws` | WebSocket bridge: text frames are JSON-RPC requests |

Example:

```bash
curl -s localhost:4000/api/generate -d '{"prompt":"landing page with 3 cards","width":800,"height":600,"name":"Landing"}'
curl -s localhost:4000/api/rpc -d '{"jsonrpc":"2.0","id":1,"method":"moonpot/list_projects"}'
```

## Design notes

- **Storage**: `Store` keeps everything in memory and snapshots to a JSON file via `save_as`/`load_from` — fast, portable, and swap-ready for PostgreSQL/Redis.
- **AI provider**: `AiProvider` trait with a deterministic `MockProvider` (offline, keyword-driven layout). A hosted LLM provider can implement the same trait.
- **KB**: bilingual tokenization (ASCII words + CJK single characters), TF bag-of-words vectors, cosine similarity — fully self-contained, no ML runtime needed.
- **MCP everywhere**: the single `@mcp.handle(store, text)` dispatcher powers the file-transport server, `POST /api/rpc`, and the `/ws` bridge, so MCP clients can attach over any transport.

## Testing

MoonPot ships a two-layer, dependency-free test suite:

```bash
# Layer 1 — selftest: 20 assertion blocks across every module
moonrun _build/wasm/debug/build/cmd/selftest/selftest.wasm
# ALL STORE + AI + SKILL + KB + MCP + CLI TESTS PASSED

# Layer 2 — e2e: boots the real server and exercises all four transports
bash e2e/run_e2e.sh
# e2e summary: PASS=24 FAIL=0
```

The selftest covers boundary inputs (empty/keyword-flood/tiny-canvas prompts),
generation determinism, a `FakeProvider` swap of the open `AiProvider` trait,
corrupted-snapshot recovery, the full MCP method matrix with JSON-RPC error
codes, KB edge cases (empty index, topk bounds, CJK queries), CLI error paths,
500-shape/Unicode/deep-nesting round-trips and HTML escaping. The e2e suite
asserts all REST endpoints plus 404/400 bodies, a WebSocket JSON-RPC
round-trip (Node ≥ 22 native WebSocket), the MCP file-transport server and a
CLI full chain with snapshot persistence.

## Docs

- [docs/changelog.md](docs/changelog.md)
- [docs/roadmap.md](docs/roadmap.md)
- [docs/long-term-plan.md](docs/long-term-plan.md) — staged plan to v1.0 with acceptance criteria and risk register

## License

Apache-2.0
