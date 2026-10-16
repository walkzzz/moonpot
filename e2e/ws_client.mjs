// e2e WebSocket client: connects to the moonpot /ws bridge, expects a
// welcome text frame, then sends a JSON-RPC request and expects a result.
const ws = new WebSocket("ws://localhost:4000/ws");
let stage = 0;
ws.onmessage = (e) => {
  stage += 1;
  if (stage === 1) {
    ws.send(
      JSON.stringify({
        jsonrpc: "2.0",
        id: 7,
        method: "moonpot/read_file",
        params: { project_id: "proj_gen_E2E", file_id: "f1" },
      }),
    );
  } else {
    const ok = e.data.includes('"result"') && e.data.includes('"E2E"');
    console.log(ok ? "WS-PASS" : "WS-FAIL: " + e.data.slice(0, 120));
    process.exit(ok ? 0 : 1);
  }
};
ws.onerror = () => {
  console.log("WS-FAIL error");
  process.exit(1);
};
setTimeout(() => {
  console.log("WS-FAIL timeout");
  process.exit(1);
}, 8000);
