import { AgentId, AgentSpec, BridgeConfig } from "./types";

function parseArgs(input: string): string[] {
  const source = input.trim();
  if (!source) {
    return [];
  }

  const args: string[] = [];
  let current = "";
  let quote: "'" | '"' | null = null;
  let escaped = false;

  for (const char of source) {
    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }

    if (char === "\\") {
      escaped = true;
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

    if (char === "'" || char === '"') {
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

function buildAgentSpec(
  id: AgentId,
  title: string,
  cmdEnv: string,
  argsEnv: string,
  fallbackCmd: string,
): AgentSpec {
  return {
    id,
    title,
    command: readString(cmdEnv, fallbackCmd),
    args: parseArgs(readString(argsEnv, "")),
  };
}

export function loadConfig(): BridgeConfig {
  const defaultTimeoutMs = readNumber("DEFAULT_TIMEOUT_MS", 45_000);
  const maxTimeoutMs = readNumber("MAX_TIMEOUT_MS", 180_000);
  if (defaultTimeoutMs > maxTimeoutMs) {
    throw new Error("DEFAULT_TIMEOUT_MS cannot be greater than MAX_TIMEOUT_MS");
  }

  return {
    host: readString("HOST", "0.0.0.0"),
    port: readNumber("PORT", 7071),
    defaultTimeoutMs,
    defaultIdleMs: readNumber("DEFAULT_IDLE_MS", 1_200),
    maxTimeoutMs,
    agents: {
      codex: buildAgentSpec(
        "codex",
        "Codex CLI",
        "AGENT_CODEX_CMD",
        "AGENT_CODEX_ARGS",
        "codex",
      ),
      qwen: buildAgentSpec(
        "qwen",
        "Qwen CLI",
        "AGENT_QWEN_CMD",
        "AGENT_QWEN_ARGS",
        "qwen",
      ),
    },
  };
}
