#!/usr/bin/env node
// WebSocket terminal server — spawns an openshell terminal session and bridges
// it to a WebSocket client (xterm.js in the browser).
//
// Security:
//   - Binds to 127.0.0.1 only (loopback) — not reachable from outside the host
//   - Requires a valid gateway auth token as ?token= query parameter
//   - Token is read from ~/openclaw-ui-url.txt at startup (same token the UI uses)
//   - The spawned command is hardcoded to "openshell term" — callers cannot choose
//
// Nginx proxies /ws/terminal?token=<hex> to this server. External access is
// authenticated by Brev Secure Links (Cloudflare Access) before reaching nginx.
//
// Usage: node server.js [--port 3001]

"use strict";

const fs = require("fs");
const path = require("path");
const WebSocket = require("ws");
const pty = require("node-pty");

const PORT = parseInt(
  process.argv.includes("--port")
    ? process.argv[process.argv.indexOf("--port") + 1]
    : "3001",
  10,
);

// Hardcoded command — never accept commands from the client.
const SHELL_CMD = "openshell";
const SHELL_ARGS = ["term"];

// ── Token authentication ──────────────────────────────────────────────
// Read the expected token from the local UI URL file. This is the same
// token the browser uses for the OpenClaw dashboard, so it's already
// known to authenticated users.

function loadExpectedToken() {
  const urlFile = path.join(
    process.env.HOME || "/home/ubuntu",
    "openclaw-ui-url.txt",
  );
  try {
    const url = fs.readFileSync(urlFile, "utf-8").trim();
    const match = url.match(/#token=([0-9a-fA-F]+)/);
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

let expectedToken = loadExpectedToken();

// Re-read the token periodically (it changes on sandbox rebuild).
setInterval(() => {
  expectedToken = loadExpectedToken();
}, 60_000);

function authenticateRequest(req) {
  if (!expectedToken) {
    // No token file yet (sandbox may not be ready). Reject all connections
    // rather than running unauthenticated.
    return false;
  }
  const url = new URL(req.url || "/", `http://127.0.0.1:${PORT}`);
  const clientToken = url.searchParams.get("token") || "";
  // Constant-time comparison to prevent timing attacks.
  if (clientToken.length !== expectedToken.length) return false;
  const a = Buffer.from(clientToken, "utf-8");
  const b = Buffer.from(expectedToken, "utf-8");
  return require("crypto").timingSafeEqual(a, b);
}

// ── Server ────────────────────────────────────────────────────────────

const wss = new WebSocket.Server({
  port: PORT,
  host: "127.0.0.1", // Loopback only — nginx proxies external traffic
});

console.log(`[terminal-server] listening on 127.0.0.1:${PORT}`);
if (expectedToken) {
  console.log("[terminal-server] token authentication enabled");
} else {
  console.log(
    "[terminal-server] WARNING: no token found — all connections will be rejected until ~/openclaw-ui-url.txt exists",
  );
}

wss.on("connection", (ws, req) => {
  if (!authenticateRequest(req)) {
    console.log("[terminal-server] rejected: invalid or missing token");
    ws.close(4001, "Unauthorized");
    return;
  }

  console.log("[terminal-server] authenticated connection");

  const shell = pty.spawn(SHELL_CMD, SHELL_ARGS, {
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
      // Raw text fallback — write directly to the PTY.
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
