export type AgentId = "codex" | "qwen";
export type ExecutionMode = "bridge" | "api";
export type AuthRole = "admin" | "user";

export interface RunResult {
  output: string;
  timedOut: boolean;
  durationMs: number;
}

export interface RunOptions {
  cwd?: string;
  timeoutMs: number;
  fullAccess?: boolean;
}

export interface AgentRunner {
  run(agentId: AgentId, prompt: string, options: RunOptions): Promise<RunResult>;
}

export interface BridgeSettings {
  url: string;
  requestTimeoutMs: number;
  autostart: boolean;
  showConsole: boolean;
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

export interface AuthTokenBinding {
  userId: string;
  role: AuthRole;
}

export interface AuthSettings {
  enabled: boolean;
  header: string;
  defaultUserId: string;
  tokens: Record<string, AuthTokenBinding>;
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
  auth: AuthSettings;
}
