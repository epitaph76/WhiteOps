import { HttpError } from "../errors";
import { AgentId, AgentRunner, RunOptions, RunResult } from "../types";

interface ApiRunnerOptions {
  runUrl: string;
  requestTimeoutMs: number;
  authHeader: string;
  authToken?: string;
}

function normalizeResult(data: unknown): RunResult {
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("API provider returned invalid response shape");
  }

  const value = data as Record<string, unknown>;
  if (typeof value.output !== "string") {
    throw new Error("API response field 'output' must be a string");
  }
  if (typeof value.timedOut !== "boolean") {
    throw new Error("API response field 'timedOut' must be a boolean");
  }
  if (typeof value.durationMs !== "number") {
    throw new Error("API response field 'durationMs' must be a number");
  }

  return {
    output: value.output,
    timedOut: value.timedOut,
    durationMs: value.durationMs,
  };
}

export class ApiRunner implements AgentRunner {
  constructor(private readonly options: ApiRunnerOptions) {}

  async run(agentId: AgentId, prompt: string, runOptions: RunOptions): Promise<RunResult> {
    const controller = new AbortController();
    const timeoutMs = this.options.requestTimeoutMs;
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    const headers: Record<string, string> = {
      "content-type": "application/json",
    };

    if (this.options.authToken) {
      headers[this.options.authHeader] = this.options.authToken;
    }

    try {
      const response = await fetch(this.options.runUrl, {
        method: "POST",
        headers,
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
          `API provider failed with status ${response.status}. Payload: ${payload}`,
        );
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(payload);
      } catch {
        throw new HttpError(502, `API provider returned non-JSON payload: ${payload}`);
      }

      return normalizeResult(parsed);
    } catch (error) {
      if (error instanceof HttpError) {
        throw error;
      }
      if (error instanceof Error && error.name === "AbortError") {
        throw new HttpError(504, `API provider request timed out after ${timeoutMs}ms`);
      }

      const message =
        error instanceof Error ? error.message : "API provider request failed";
      throw new HttpError(502, `API provider request failed: ${message}`);
    } finally {
      clearTimeout(timeout);
    }
  }
}
