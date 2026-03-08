export type AgentId = "codex" | "qwen";
export type ExecutionMode = "bridge" | "api";

export interface RunResult {
  output: string;
  timedOut: boolean;
  durationMs: number;
}

export interface RunOptions {
  cwd?: string;
  timeoutMs: number;
}

export interface AgentRunner {
  run(agentId: AgentId, prompt: string, options: RunOptions): Promise<RunResult>;
}

export interface BridgeSettings {
  url: string;
  requestTimeoutMs: number;
  autostart: boolean;
  startCommand: string;
  startArgs: string[];
  startCwd: string;
  startupTimeoutMs: number;
  healthcheckIntervalMs: number;
}

export interface ApiSettings {
  runUrl: string;
  requestTimeoutMs: number;
  authHeader: string;
  authToken?: string;
}

export interface OrchestratorConfig {
  host: string;
  port: number;
  mode: ExecutionMode;
  defaultCwd?: string;
  managerTimeoutMs: number;
  workerTimeoutMs: number;
  maxTimeoutMs: number;
  bridge: BridgeSettings;
  api: ApiSettings;
}
