import { HttpError } from "../errors";
import { AgentId, AgentRunner, RunOptions, RunResult } from "../types";

interface BridgeRunnerOptions {
  baseUrl: string;
  requestTimeoutMs: number;
}

function normalizeResult(data: unknown): RunResult {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("Bridge returned invalid response shape");
  }

  const value = data as Record<string, unknown>;
  if (typeof value.output !== "string") {
    throw new Error("Bridge response field 'output' must be a string");
  }
  if (typeof value.timedOut !== "boolean") {
    throw new Error("Bridge response field 'timedOut' must be a boolean");
  }
  if (typeof value.durationMs !== "number") {
    throw new Error("Bridge response field 'durationMs' must be a number");
  }

  return {
    output: value.output,
    timedOut: value.timedOut,
    durationMs: value.durationMs,
  };
}

export class BridgeRunner implements AgentRunner {
  constructor(private readonly options: BridgeRunnerOptions) {}

  async run(agentId: AgentId, prompt: string, runOptions: RunOptions): Promise<RunResult> {
    const controller = new AbortController();
    const timeoutMs = this.options.requestTimeoutMs;
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    try {
      const response = await fetch(`${this.options.baseUrl}/runs`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
        },
        body: JSON.stringify({
          agentId,
          prompt,
          cwd: runOptions.cwd,
          timeoutMs: runOptions.timeoutMs,
          fullAccess: runOptions.fullAccess === true,
        }),
        signal: controller.signal,
      });

      const payload = await response.text();
      if (!response.ok) {
        throw new HttpError(
          502,
          `Bridge /runs failed with status ${response.status}. Payload: ${payload}`,
        );
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(payload);
      } catch {
        throw new HttpError(502, `Bridge returned non-JSON payload: ${payload}`);
      }

      return normalizeResult(parsed);
    } catch (error) {
      if (error instanceof HttpError) {
        throw error;
      }
      if (error instanceof Error && error.name === "AbortError") {
        throw new HttpError(504, `Bridge request timed out after ${timeoutMs}ms`);
      }
      const message =
        error instanceof Error ? error.message : "Bridge request failed";
      throw new HttpError(502, `Bridge request failed: ${message}`);
    } finally {
      clearTimeout(timeout);
    }
  }
}
