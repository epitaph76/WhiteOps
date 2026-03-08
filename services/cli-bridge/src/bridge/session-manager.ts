import { randomUUID } from "node:crypto";

import { BridgeConfig, RunOptions, RunResult, SessionSnapshot, AgentId } from "../types";
import { CliSession } from "./cli-session";
import { HttpError } from "../errors";
import { runAgentOneShot } from "./one-shot-runner";

interface SessionRecord {
  session: CliSession;
  createdAt: Date;
}

interface NormalizedRunOptions {
  timeoutMs: number;
  idleMs: number;
}

export class SessionManager {
  private readonly sessions = new Map<string, SessionRecord>();

  constructor(private readonly config: BridgeConfig) {}

  listAgents() {
    return Object.values(this.config.agents);
  }

  listSessions(): SessionSnapshot[] {
    return [...this.sessions.entries()].map(([id, record]) => ({
      id,
      agentId: record.session.agent.id,
      agentTitle: record.session.agent.title,
      cwd: record.session.cwd,
      busy: record.session.isBusy,
      alive: record.session.isAlive,
      createdAt: record.createdAt.toISOString(),
    }));
  }

  createSession(agentId: AgentId, cwd?: string): SessionSnapshot {
    const spec = this.config.agents[agentId];
    if (!spec) {
      throw new HttpError(400, `Unsupported agent: ${agentId}`);
    }

    const sessionId = randomUUID();
    let session: CliSession;
    try {
      session = new CliSession({
        id: sessionId,
        agent: spec,
        cwd,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Failed to start CLI session";
      throw new HttpError(
        500,
        `Cannot start ${spec.title}. Check command '${spec.command}'. ${message}`,
      );
    }

    this.sessions.set(sessionId, {
      session,
      createdAt: new Date(),
    });

    session.on("exit", () => {
      this.sessions.delete(sessionId);
    });

    return {
      id: sessionId,
      agentId: spec.id,
      agentTitle: spec.title,
      cwd,
      busy: false,
      alive: true,
      createdAt: new Date().toISOString(),
    };
  }

  closeSession(sessionId: string): boolean {
    const record = this.sessions.get(sessionId);
    if (!record) {
      return false;
    }

    record.session.close();
    this.sessions.delete(sessionId);
    return true;
  }

  closeAll(): void {
    for (const record of this.sessions.values()) {
      record.session.close();
    }
    this.sessions.clear();
  }

  async runInSession(
    sessionId: string,
    prompt: string,
    options: RunOptions = {},
  ): Promise<RunResult> {
    const record = this.sessions.get(sessionId);
    if (!record) {
      throw new HttpError(404, `Session ${sessionId} was not found`);
    }
    if (!record.session.isAlive) {
      throw new HttpError(409, `Session ${sessionId} is not alive`);
    }

    const normalized = this.normalizeRunOptions(options);
    return record.session.sendPrompt(prompt, normalized);
  }

  async runOnce(
    agentId: AgentId,
    prompt: string,
    options: RunOptions & { cwd?: string } = {},
  ): Promise<RunResult> {
    const spec = this.config.agents[agentId];
    if (!spec) {
      throw new HttpError(400, `Unsupported agent: ${agentId}`);
    }

    const normalized = this.normalizeRunOptions(options);
    try {
      return await runAgentOneShot(spec, {
        prompt,
        timeoutMs: normalized.timeoutMs,
        cwd: options.cwd,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Failed to run one-shot request";
      throw new HttpError(
        500,
        `Cannot run ${spec.title} one-shot. Check command '${spec.command}'. ${message}`,
      );
    }
  }

  private normalizeRunOptions(options: RunOptions): NormalizedRunOptions {
    const timeoutMs = options.timeoutMs ?? this.config.defaultTimeoutMs;
    const idleMs = options.idleMs ?? this.config.defaultIdleMs;

    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
      throw new HttpError(400, "timeoutMs must be a positive number");
    }

    if (!Number.isFinite(idleMs) || idleMs <= 0) {
      throw new HttpError(400, "idleMs must be a positive number");
    }

    if (timeoutMs > this.config.maxTimeoutMs) {
      throw new HttpError(
        400,
        `timeoutMs cannot exceed MAX_TIMEOUT_MS (${this.config.maxTimeoutMs})`,
      );
    }

    return {
      timeoutMs: Math.floor(timeoutMs),
      idleMs: Math.floor(idleMs),
    };
  }
}
