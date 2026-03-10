import { spawn } from "node:child_process";

import { AgentSpec, RunResult } from "../types";
import { resolveCommandForSpawn } from "./command-resolver";

interface OneShotOptions {
  prompt: string;
  timeoutMs: number;
  cwd?: string;
  fullAccess?: boolean;
}

function normalizePromptForCliArg(prompt: string): string {
  return prompt.replace(/\r?\n+/g, " ").replace(/\s{2,}/g, " ").trim();
}

function applyCodexAccessFlags(baseArgs: string[], fullAccess: boolean): string[] {
  if (!fullAccess) {
    return baseArgs;
  }

  return [
    ...baseArgs,
    "--sandbox",
    "danger-full-access",
    "--approval",
    "never",
  ];
}

function buildOneShotArgs(agent: AgentSpec, prompt: string, options: OneShotOptions): string[] {
  const normalizedPrompt = normalizePromptForCliArg(prompt);

  if (agent.id === "qwen") {
    return [...agent.args, "--output-format", "text", normalizedPrompt];
  }

  if (agent.id === "codex") {
    const codexArgs = applyCodexAccessFlags(agent.args, options.fullAccess === true);
    return [...codexArgs, "exec", normalizedPrompt];
  }

  return [...agent.args, normalizedPrompt];
}

export function runAgentOneShot(
  agent: AgentSpec,
  options: OneShotOptions,
): Promise<RunResult> {
  const prompt = options.prompt.trim();
  if (!prompt) {
    throw new Error("Prompt cannot be empty");
  }

  const command = resolveCommandForSpawn(agent.command);
  const args = buildOneShotArgs(agent, prompt, options);
  const isWindows = process.platform === "win32";
  const spawnCommand = isWindows ? "cmd.exe" : command;
  const spawnArgs = isWindows
    ? ["/d", "/s", "/c", command, ...args]
    : args;
  const startedAt = Date.now();

  return new Promise<RunResult>((resolve, reject) => {
    const chunks: string[] = [];
    let timedOut = false;
    let settled = false;

    const child = spawn(spawnCommand, spawnArgs, {
      cwd: options.cwd ?? process.cwd(),
      env: process.env,
      shell: false,
      windowsHide: false,
    });

    const closeGuard = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => {
        child.kill("SIGKILL");
      }, 500);
    }, options.timeoutMs);

    child.stdout?.on("data", (chunk) => {
      chunks.push(String(chunk));
    });

    child.stderr?.on("data", (chunk) => {
      chunks.push(String(chunk));
    });

    child.on("error", (error) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(closeGuard);
      reject(error);
    });

    child.on("close", (code, signal) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(closeGuard);

      if (!timedOut && code !== 0) {
        chunks.push(`\n[cli-exit code=${code ?? "null"} signal=${signal ?? "null"}]\n`);
      }

      resolve({
        output: chunks.join(""),
        timedOut,
        durationMs: Date.now() - startedAt,
      });
    });
  });
}
