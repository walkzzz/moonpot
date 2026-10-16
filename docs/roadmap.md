# Roadmap

MoonPot MVP (v0.1.0) is complete: backend + AI / Skill / MCP / CLI / KB, verified by the selftest suite and live smoke tests of every transport.

## v0.2 — AI upgrades

- [ ] Hosted LLM provider behind the existing `AiProvider` trait (mock stays as offline fallback).
- [ ] Streaming generation over the `/ws` bridge (progress frames while a design is built).
- [ ] Smarter KB: inverse document frequency weighting and n-gram tokens for CJK.

## v0.3 — Persistence & collaboration

- [ ] Swap-in PostgreSQL store implementing the `Store` trait (schema: projects / files / pages / shapes).
- [ ] Optimistic concurrency: file revisions + patch endpoint (`ShapePatch` is already in the model).
- [ ] Multi-client WebSocket rooms: broadcast shape edits to all peers in a project channel.

## v0.4 — Surface

- [ ] Static asset hosting from the crescent server (rendered HTML previews at `/preview/:pid/:fid`).
- [ ] `moonpot render` CLI subcommand: design tree → standalone HTML file.
- [ ] Export: SVG output alongside the existing HTML renderer.

## v0.5 — Operations

- [ ] Dockerfile + compose file for the HTTP server.
- [ ] Graceful shutdown hook (crescent `shutdown` queue) and health-checked readiness.
- [ ] Structured request logging middleware.

## Non-goals (for now)

- Interactive canvas frontend — MoonPot is backend-first; the frontend stays out of scope until the core API stabilizes.
