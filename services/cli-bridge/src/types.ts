export type AgentId = "codex" | "qwen";

export interface AgentSpec {
  id: AgentId;
  title: string;
  command: string;
  args: string[];
}

export interface BridgeConfig {
  host: string;
  port: number;
  defaultTimeoutMs: number;
  defaultIdleMs: number;
  maxTimeoutMs: number;
  agents: Record<AgentId, AgentSpec>;
}

export interface SessionSnapshot {
  id: string;
  agentId: AgentId;
  agentTitle: string;
  cwd?: string;
  busy: boolean;
  alive: boolean;
  createdAt: string;
}

export interface RunResult {
  output: string;
  timedOut: boolean;
  durationMs: number;
}

export interface RunOptions {
  timeoutMs?: number;
  idleMs?: number;
}
