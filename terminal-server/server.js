#!/usr/bin/env node
// WebSocket terminal server — spawns a PTY process and bridges it to a
// WebSocket client (xterm.js in the browser). Nginx proxies /ws/terminal here.
//
// Usage: node server.js [--port 3001]
//
// Query params:
//   ?cmd=openshell+term   (default: "openshell term")

const WebSocket = require("ws");
const pty = require("node-pty");

const PORT = parseInt(
  process.argv.includes("--port")
    ? process.argv[process.argv.indexOf("--port") + 1]
    : "3001",
  10,
);

const wss = new WebSocket.Server({ port: PORT });
console.log(`[terminal-server] listening on port ${PORT}`);

wss.on("connection", (ws, req) => {
  const url = new URL(req.url || "/", `http://localhost:${PORT}`);
  const cmdParam = url.searchParams.get("cmd") || "openshell term";
  const parts = cmdParam.split(" ").filter(Boolean);
  const cmd = parts[0];
  const args = parts.slice(1);

  console.log(`[terminal-server] new connection: ${cmd} ${args.join(" ")}`);

  const shell = pty.spawn(cmd, args, {
    name: "xterm-256color",
    cols: 120,
    rows: 40,
    cwd: process.env.HOME || "/home/ubuntu",
    env: {
      ...process.env,
      TERM: "xterm-256color",
    },
  });

  shell.onData((data) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: "output", data }));
    }
  });

  shell.onExit(({ exitCode }) => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: "exit", code: exitCode }));
      ws.close();
    }
  });

  ws.on("message", (msg) => {
    try {
      const parsed = JSON.parse(msg.toString());
      if (parsed.type === "input") {
        shell.write(parsed.data);
      } else if (parsed.type === "resize" && parsed.cols && parsed.rows) {
        shell.resize(parsed.cols, parsed.rows);
      }
    } catch {
      shell.write(msg.toString());
    }
  });

  ws.on("close", () => {
    console.log("[terminal-server] connection closed");
    shell.kill();
  });

  ws.on("error", (err) => {
    console.error("[terminal-server] error:", err.message);
    shell.kill();
  });
});

process.on("SIGTERM", () => {
  console.log("[terminal-server] shutting down");
  wss.close();
  process.exit(0);
});
