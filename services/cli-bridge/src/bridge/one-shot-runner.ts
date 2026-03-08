import { spawn } from "node:child_process";

import { AgentSpec, RunResult } from "../types";
import { resolveCommandForSpawn } from "./command-resolver";

interface OneShotOptions {
  prompt: string;
  timeoutMs: number;
  cwd?: string;
}

function buildOneShotArgs(agent: AgentSpec, prompt: string): string[] {
  if (agent.id === "qwen") {
    return [...agent.args, "--output-format", "text", prompt];
  }

  if (agent.id === "codex") {
    return [...agent.args, "exec", prompt];
  }

  return [...agent.args, prompt];
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
  const args = buildOneShotArgs(agent, prompt);
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
      windowsHide: true,
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
