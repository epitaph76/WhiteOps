import path from "node:path";

import { AuthRole, ExecutionMode, OrchestratorConfig } from "./types";

function parseArgs(input: string): string[] {
  const source = input.trim();
  if (!source) {
    return [];
  }

  const args: string[] = [];
  let current = "";
  let quote: "'" | "\"" | null = null;
  let escaped = false;

  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];

    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }

    if (char === "\\") {
      const next = source[i + 1];
      const shouldEscapeInQuote =
        Boolean(quote) && (next === quote || next === "\\");
      const shouldEscapeWhitespace = !quote && Boolean(next && /\s/.test(next));

      if (shouldEscapeInQuote || shouldEscapeWhitespace) {
        escaped = true;
        continue;
      }

      current += char;
      continue;
    }

    if (quote) {
      if (char === quote) {
        quote = null;
      } else {
        current += char;
      }
      continue;
    }

    if (char === "'" || char === "\"") {
      quote = char;
      continue;
    }

    if (/\s/.test(char)) {
      if (current.length > 0) {
        args.push(current);
        current = "";
      }
      continue;
    }

    current += char;
  }

  if (current.length > 0) {
    args.push(current);
  }

  return args;
}

function readNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`Environment variable ${name} must be a positive number`);
  }

  return Math.floor(value);
}

function readString(name: string, fallback: string): string {
  const raw = process.env[name];
  return raw && raw.trim() ? raw.trim() : fallback;
}

function readOptionalString(name: string): string | undefined {
  const raw = process.env[name];
  if (!raw) {
    return undefined;
  }
  const value = raw.trim();
  return value || undefined;
}

function readBoolean(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }

  const normalized = raw.trim().toLowerCase();
  if (normalized === "1" || normalized === "true" || normalized === "yes") {
    return true;
  }
  if (normalized === "0" || normalized === "false" || normalized === "no") {
    return false;
  }

  throw new Error(`Environment variable ${name} must be boolean-like`);
}

function readMode(): ExecutionMode {
  const raw = readString("EXECUTION_MODE", "bridge").toLowerCase();
  if (raw === "bridge" || raw === "api") {
    return raw;
  }
  throw new Error("EXECUTION_MODE must be one of: bridge, api");
}

function parseAuthRole(input: string | undefined): AuthRole {
  if (!input) {
    return "user";
  }

  const normalized = input.trim().toLowerCase();
  if (normalized === "admin" || normalized === "user") {
    return normalized;
  }

  throw new Error(`Unsupported auth role '${input}' in AUTH_TOKENS`);
}

function parseAuthTokens(input: string | undefined): Record<string, { userId: string; role: AuthRole }> {
  if (!input || !input.trim()) {
    return {};
  }

  const tokens: Record<string, { userId: string; role: AuthRole }> = {};
  const entries = input
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);

  for (const entry of entries) {
    const [token, userId, role] = entry.split(":");
    if (!token || !userId) {
      throw new Error(
        "AUTH_TOKENS format must be token:userId[:role],token2:userId2[:role]",
      );
    }

    const normalizedToken = token.trim();
    const normalizedUserId = userId.trim();
    if (!normalizedToken || !normalizedUserId) {
      throw new Error(
        "AUTH_TOKENS format must be token:userId[:role],token2:userId2[:role]",
      );
    }

    tokens[normalizedToken] = {
      userId: normalizedUserId,
      role: parseAuthRole(role),
    };
  }

  return tokens;
}

function resolveDefaultBridgeCwd(): string {
  return path.resolve(__dirname, "..", "..", "cli-bridge");
}

export function loadConfig(): OrchestratorConfig {
  const managerTimeoutMs = readNumber("MANAGER_TIMEOUT_MS", 60_000);
  const workerTimeoutMs = readNumber("WORKER_TIMEOUT_MS", 120_000);
  const maxTimeoutMs = readNumber("MAX_TIMEOUT_MS", 300_000);

  if (managerTimeoutMs > maxTimeoutMs) {
    throw new Error("MANAGER_TIMEOUT_MS cannot be greater than MAX_TIMEOUT_MS");
  }
  if (workerTimeoutMs > maxTimeoutMs) {
    throw new Error("WORKER_TIMEOUT_MS cannot be greater than MAX_TIMEOUT_MS");
  }

  const mode = readMode();

  const config: OrchestratorConfig = {
    host: readString("HOST", "0.0.0.0"),
    port: readNumber("PORT", 7081),
    mode,
    defaultCwd: readOptionalString("DEFAULT_CWD"),
    managerTimeoutMs,
    workerTimeoutMs,
    maxTimeoutMs,
    bridge: {
      url: readString("BRIDGE_URL", "http://127.0.0.1:7071"),
      requestTimeoutMs: readNumber("BRIDGE_REQUEST_TIMEOUT_MS", 180_000),
      autostart: readBoolean("BRIDGE_AUTOSTART", true),
      showConsole: readBoolean("BRIDGE_SHOW_CONSOLE", true),
      startCommand: readString("BRIDGE_START_CMD", "node"),
      startArgs: parseArgs(
        readString(
          "BRIDGE_START_ARGS",
          "node_modules/tsx/dist/cli.mjs watch src/index.ts",
        ),
      ),
      startCwd: readString("BRIDGE_START_CWD", resolveDefaultBridgeCwd()),
      startupTimeoutMs: readNumber("BRIDGE_STARTUP_TIMEOUT_MS", 45_000),
      healthcheckIntervalMs: readNumber("BRIDGE_HEALTHCHECK_INTERVAL_MS", 1_000),
    },
    api: {
      runUrl: readString("API_RUN_URL", ""),
      requestTimeoutMs: readNumber("API_REQUEST_TIMEOUT_MS", 180_000),
      authHeader: readString("API_AUTH_HEADER", "Authorization"),
      authToken: readOptionalString("API_AUTH_TOKEN"),
    },
    auth: {
      enabled: readBoolean("AUTH_ENABLED", false),
      header: readString("AUTH_HEADER", "Authorization"),
      defaultUserId: readString("AUTH_DEFAULT_USER_ID", "local-dev"),
      tokens: parseAuthTokens(readOptionalString("AUTH_TOKENS")),
    },
  };

  if (mode === "api" && !config.api.runUrl) {
    throw new Error("API_RUN_URL is required when EXECUTION_MODE=api");
  }

  return config;
}
