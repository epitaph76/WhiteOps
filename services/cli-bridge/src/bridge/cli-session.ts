import { EventEmitter } from "node:events";
import * as pty from "node-pty";

import { AgentSpec, RunResult } from "../types";

interface SessionOptions {
  id: string;
  agent: AgentSpec;
  cwd?: string;
}

interface PromptOptions {
  timeoutMs: number;
  idleMs: number;
}

export class CliSession extends EventEmitter {
  readonly id: string;
  readonly agent: AgentSpec;
  readonly cwd?: string;

  private readonly ptyProcess: pty.IPty;
  private queue: Promise<void> = Promise.resolve();
  private closed = false;
  private busy = false;

  constructor(options: SessionOptions) {
    super();
    this.id = options.id;
    this.agent = options.agent;
    this.cwd = options.cwd;

    this.ptyProcess = pty.spawn(options.agent.command, options.agent.args, {
      cwd: options.cwd ?? process.cwd(),
      env: process.env as Record<string, string>,
      name: "xterm-color",
      cols: 120,
      rows: 40,
    });

    this.ptyProcess.onExit(({ exitCode, signal }) => {
      this.closed = true;
      this.emit("exit", { exitCode, signal });
    });
  }

  get isBusy(): boolean {
    return this.busy;
  }

  get isAlive(): boolean {
    return !this.closed;
  }

  sendPrompt(prompt: string, options: PromptOptions): Promise<RunResult> {
    const sanitized = prompt.trim();
    if (!sanitized) {
      throw new Error("Prompt cannot be empty");
    }

    return this.enqueue(() => this.executePrompt(sanitized, options));
  }

  close(): void {
    if (this.closed) {
      return;
    }

    this.closed = true;
    try {
      this.ptyProcess.kill();
    } catch {
      // Ignore kill errors when process already exited.
    }
  }

  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const next = this.queue.then(task, task);
    this.queue = next.then(
      () => undefined,
      () => undefined,
    );
    return next;
  }

  private executePrompt(prompt: string, options: PromptOptions): Promise<RunResult> {
    if (this.closed) {
      throw new Error(`Session ${this.id} is not alive`);
    }

    this.busy = true;
    const startedAt = Date.now();
    const chunks: string[] = [];

    return new Promise<RunResult>((resolve) => {
      let finished = false;
      let idleTimer: NodeJS.Timeout | undefined;
      let timeoutTimer: NodeJS.Timeout | undefined;

      const finish = (timedOut: boolean): void => {
        if (finished) {
          return;
        }
        finished = true;
        this.busy = false;

        if (idleTimer) {
          clearTimeout(idleTimer);
        }
        if (timeoutTimer) {
          clearTimeout(timeoutTimer);
        }

        outputListener.dispose();
        exitListener.dispose();

        resolve({
          output: chunks.join(""),
          timedOut,
          durationMs: Date.now() - startedAt,
        });
      };

      const bumpIdle = (): void => {
        if (idleTimer) {
          clearTimeout(idleTimer);
        }
        idleTimer = setTimeout(() => finish(false), options.idleMs);
      };

      const outputListener = this.ptyProcess.onData((chunk) => {
        chunks.push(chunk);
        bumpIdle();
      });

      const exitListener = this.ptyProcess.onExit(({ exitCode, signal }) => {
        this.closed = true;
        chunks.push(`\n[cli-exit code=${exitCode} signal=${signal}]\n`);
        finish(false);
      });

      timeoutTimer = setTimeout(() => finish(true), options.timeoutMs);

      const payload = prompt.endsWith("\n") ? prompt : `${prompt}\n`;
      this.ptyProcess.write(payload.replace(/\n/g, "\r"));
    });
  }
}
