#!/usr/bin/env bash
# MoonPot end-to-end tests: REST + WebSocket + MCP (file transport) + CLI.
#
# Usage:  bash e2e/run_e2e.sh
# Env:    NODE_BIN  path to a Node >= 22 binary (for the WebSocket client)
# Requires: moonrun + curl on PATH, and a prior `moon build`.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="${NODE_BIN:-C:/Users/Administrator/.workbuddy/binaries/node/versions/22.22.2-2/node.exe}"
BASE="http://localhost:4000"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; }
assert_contains() { # label haystack needle
  if printf '%s' "$2" | grep -qF -- "$3"; then
    ok "$1"
  else
    fail "$1 (missing: $3)"
  fi
}

TMP="$ROOT/.e2e_tmp"
cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"
# wasm paths are relative to $TMP (one level up is the repo root)
WS_MJS="$(cygpath -m "$ROOT/e2e/ws_client.mjs" 2>/dev/null || echo "$ROOT/e2e/ws_client.mjs")"

echo "== [e2e 1/4] REST + WebSocket server =="

# refuse to run if the port is already taken
if curl -s -m 2 "$BASE/health" >/dev/null 2>&1; then
  echo "  FAIL - port 4000 already in use; stop the other server first"
  exit 1
fi

moonrun "../_build/wasm/debug/build/server/server.wasm" >server.log 2>&1 &
SERVER_PID=$!
READY=0
for _ in $(seq 1 60); do
  if curl -s -m 2 "$BASE/health" >/dev/null 2>&1; then READY=1; break; fi
  sleep 0.5
done
if [ "$READY" = "1" ]; then
  ok "server up on :4000"
else
  fail "server did not start"
  cat server.log
  exit 1
fi

H=$(curl -s "$BASE/health")
assert_contains "GET /health" "$H" '"status":"up"'

R=$(curl -s -X POST "$BASE/api/generate" -d '{"prompt":"landing page with 3 cards and a button","width":800,"height":600,"name":"E2E"}')
assert_contains "POST /api/generate" "$R" '"project"'
assert_contains "generate notes" "$R" '"notes"'

G=$(curl -s "$BASE/api/projects/proj_gen_E2E/files/f1")
assert_contains "GET generated file" "$G" '"E2E"'

S=$(curl -s -X POST "$BASE/api/projects/proj_gen_E2E/files/f1/skills/flatten")
assert_contains "POST run-skill flatten" "$S" '"applied":"flatten"'

K=$(curl -s -X POST "$BASE/api/kb/query" -d '{"query":"MoonBit extern C","topk":1,"docs":[{"id":"d1","title":"MoonBit FFI","body":"MoonBit calls C through extern functions."}]}')
assert_contains "POST /api/kb/query" "$K" '"MoonBit FFI"'

RPC=$(curl -s -X POST "$BASE/api/rpc" -d '{"jsonrpc":"2.0","id":1,"method":"moonpot/list_projects"}')
assert_contains "POST /api/rpc" "$RPC" '"result"'
assert_contains "rpc sees generated project" "$RPC" 'proj_gen_E2E'

SK=$(curl -s "$BASE/api/skills")
assert_contains "GET /api/skills" "$SK" 'normalize-names'

N404=$(curl -s "$BASE/api/projects/ghost/files/nofile")
assert_contains "404 error body" "$N404" '"error"'

B400=$(curl -s -X POST "$BASE/api/generate" -d 'oops')
assert_contains "400 invalid json" "$B400" '"error"'

WS_OUT=$("$NODE_BIN" "$WS_MJS" 2>&1 | tail -1)
assert_contains "WS /ws json-rpc round-trip" "$WS_OUT" "WS-PASS"

kill "$SERVER_PID" 2>/dev/null
for _ in $(seq 1 10); do
  curl -s -m 1 "$BASE/health" >/dev/null 2>&1 || break
  sleep 0.5
done
echo "  (server stopped)"

echo "== [e2e 2/4] MCP file transport =="
cat >mcp_in.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"moonpot/list_projects"}
{"jsonrpc":"2.0","id":2,"method":"moonpot/read_file","params":{"project_id":"demo","file_id":"home"}}
{"jsonrpc":"2.0","id":3,"method":"moonpot/unknown"}
EOF
MCP_OUT=$(moonrun "../_build/wasm/debug/build/cmd/mcpserver/mcpserver.wasm" 2>&1)
assert_contains "mcp list_projects" "$MCP_OUT" '"demo"'
assert_contains "mcp read_file" "$MCP_OUT" '"Home Page"'
assert_contains "mcp unknown -> -32601" "$MCP_OUT" '-32601'

echo "== [e2e 3/4] CLI full chain =="
CLI="../_build/wasm/debug/build/cmd/cli/cli.wasm"
O1=$(moonrun "$CLI" init --store s.json 2>&1)
assert_contains "cli init" "$O1" "initialized s.json"
O2=$(moonrun "$CLI" new-project Solo --store s.json 2>&1)
assert_contains "cli new-project" "$O2" "created project proj_Solo"
O3=$(moonrun "$CLI" generate "landing page with 3 cards" --name Solo2 --store s.json 2>&1)
assert_contains "cli generate" "$O3" "generated project proj_gen_Solo2"
O4=$(moonrun "$CLI" run-skill proj_gen_Solo2 f1 flatten --store s.json 2>&1)
assert_contains "cli run-skill" "$O4" "applied skill 'flatten'"
if grep -qF 'proj_gen_Solo2' s.json; then
  ok "cli store snapshot persisted"
else
  fail "cli store snapshot persisted"
fi
cat >docs.json <<'EOF'
[{"id":"d1","title":"MoonBit Docs","body":"MoonBit compiles to wasm fast and small."}]
EOF
O5=$(moonrun "$CLI" ask "MoonBit wasm" --docs-file docs.json --topk 1 2>&1)
assert_contains "cli ask (RAG)" "$O5" "[MoonBit Docs]"
O6=$(moonrun "$CLI" bogus 2>&1)
assert_contains "cli bogus subcommand" "$O6" "unknown subcommand: bogus"

echo "== [e2e 4/4] selftest suite =="
ST=$(moonrun "../_build/wasm/debug/build/cmd/selftest/selftest.wasm" 2>&1 | tail -1)
assert_contains "selftest final line" "$ST" "ALL STORE + AI + SKILL + KB + MCP + CLI TESTS PASSED"

echo ""
echo "e2e summary: PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "E2E ALL PASSED"
  exit 0
else
  echo "E2E FAILURES PRESENT"
  exit 1
fi
