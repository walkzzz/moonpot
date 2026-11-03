// e2e WebSocket client for /ws/gen streaming generate.
// Connects, sends a generate request, and verifies the progressive
// start -> progress -> done frame sequence.
const ws = new WebSocket("ws://localhost:4000/ws/gen");
ws.onopen = () => {
  ws.send(
    JSON.stringify({
      type: "generate",
      prompt: "landing page with 3 cards and a button",
      width: 800,
      height: 600,
      name: "E2EWS",
    }),
  );
};
ws.onmessage = (e) => {
  let msg;
  try {
    msg = JSON.parse(e.data);
  } catch {
    return; // ignore the non-JSON welcome/text frames
  }
  if (msg.type === "ready" || msg.type === "start") {
    return;
  }
  if (msg.type === "progress") {
    if (!(msg.stage === "layout" && typeof msg.shapes === "number" && msg.shapes > 0)) {
      console.log("WSGEN-FAIL progress: " + e.data.slice(0, 120));
      process.exit(1);
    }
    return;
  }
  if (msg.type === "done") {
    if (msg.project && msg.project.files && msg.project.files.length > 0) {
      console.log("WSGEN-PASS");
      process.exit(0);
    }
    console.log("WSGEN-FAIL done missing project/files: " + e.data.slice(0, 120));
    process.exit(1);
  }
  console.log("WSGEN-FAIL unexpected: " + e.data.slice(0, 120));
  process.exit(1);
};
ws.onerror = () => {
  console.log("WSGEN-FAIL error");
  process.exit(1);
};
setTimeout(() => {
  console.log("WSGEN-FAIL timeout");
  process.exit(1);
}, 8000);
