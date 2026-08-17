#!/usr/bin/env node
// WebSocket terminal server — launches the selected sandbox through NemoClaw
// and bridges the agent-aware terminal session to xterm.js in the browser.
//
// Security:
//   - Binds to 127.0.0.1 only (loopback) — not reachable from outside the host
//   - Requires an independent host terminal token as ?token= query parameter
//   - Token is read from ~/.nemoclaw/terminal-access-token at startup
//   - The command is hardcoded to `nemoclaw launch <configured-sandbox>`
//
// Nginx proxies /ws/terminal?token=<hex> to this server. External access is
// authenticated by Brev Secure Links (Cloudflare Access) before reaching nginx.
//
// Usage: node server.js [--port 3001]

"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const WebSocket = require("ws");
const pty = require("node-pty");

const PORT = parseInt(
  process.argv.includes("--port")
    ? process.argv[process.argv.indexOf("--port") + 1]
    : "3001",
  10,
);

const HOME_DIR = process.env.HOME || "/home/ubuntu";

// Hardcoded command - never accept commands from the client.
// Use full path since systemd services don't inherit the user's shell PATH.
const SANDBOX_NAME = process.env.NEMOCLAW_SANDBOX_NAME || "";
if (SANDBOX_NAME && !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(SANDBOX_NAME)) {
  throw new Error("invalid NEMOCLAW_SANDBOX_NAME");
}
const SHELL_CMD = `${HOME_DIR}/.local/bin/nemoclaw`;
const SHELL_ARGS = SANDBOX_NAME ? ["launch", SANDBOX_NAME] : ["launch"];
const TERMINAL_ENV = Object.freeze({
  HOME: HOME_DIR,
  USER: "ubuntu",
  LOGNAME: "ubuntu",
  SHELL: "/bin/bash",
  PATH: `${HOME_DIR}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`,
  TERM: "xterm-256color",
  LANG: process.env.LANG || "C.UTF-8",
  ...(SANDBOX_NAME ? { NEMOCLAW_SANDBOX_NAME: SANDBOX_NAME } : {}),
});

// ── Token authentication ──────────────────────────────────────────────
// Keep browser-terminal authorization separate from any agent dashboard or API
// token. That makes the terminal available to gateway and terminal runtimes
// without reusing a more privileged agent credential.

function loadExpectedToken() {
  const tokenFile = path.join(HOME_DIR, ".nemoclaw", "terminal-access-token");
  try {
    const token = fs.readFileSync(tokenFile, "utf-8").trim();
    return /^[A-Za-z0-9._~+=/-]+$/.test(token) ? token : null;
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
  return crypto.timingSafeEqual(a, b);
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
    "[terminal-server] WARNING: no token found — all connections will be rejected until ~/.nemoclaw/terminal-access-token exists",
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
    cwd: HOME_DIR,
    env: TERMINAL_ENV,
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
