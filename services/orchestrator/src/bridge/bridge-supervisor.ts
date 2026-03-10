import {
  spawn,
  execFileSync,
  ChildProcess,
} from "node:child_process";

import { BridgeSettings } from "../types";

interface BridgeSupervisorStatus {
  healthy: boolean;
  managedProcessRunning: boolean;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function checkHealth(baseUrl: string): Promise<boolean> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2_500);

  try {
    const response = await fetch(`${baseUrl}/health`, {
      method: "GET",
      signal: controller.signal,
    });
    return response.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timeout);
  }
}

export class BridgeSupervisor {
  private child?: ChildProcess;
  private startingPromise?: Promise<void>;
  private startupLogs: string[] = [];

  constructor(private readonly config: BridgeSettings) {}

  async status(): Promise<BridgeSupervisorStatus> {
    return {
      healthy: await checkHealth(this.config.url),
      managedProcessRunning: Boolean(this.child && this.child.exitCode === null),
    };
  }

  async ensureReady(): Promise<void> {
    if (await checkHealth(this.config.url)) {
      return;
    }

    if (!this.config.autostart) {
      throw new Error(
        `Bridge is not reachable at ${this.config.url} and BRIDGE_AUTOSTART=false`,
      );
    }

    if (!this.startingPromise) {
      this.startingPromise = this.startAndWait();
    }

    try {
      await this.startingPromise;
    } finally {
      this.startingPromise = undefined;
    }
  }

  stop(): void {
    this.killManagedProcess();
  }

  private async startAndWait(): Promise<void> {
    if (!this.child || this.child.killed) {
      this.startBridgeProcess();
    }

    const startedAt = Date.now();
    while (Date.now() - startedAt <= this.config.startupTimeoutMs) {
      if (await checkHealth(this.config.url)) {
        return;
      }
      if (!this.child || this.child.killed) {
        break;
      }
      await sleep(this.config.healthcheckIntervalMs);
    }

    const logs = this.startupLogs.join("").trim();
    this.killManagedProcess();
    if (logs) {
      throw new Error(
        `Bridge did not become healthy within ${this.config.startupTimeoutMs}ms. Startup logs: ${logs}`,
      );
    }
    throw new Error(`Bridge did not become healthy within ${this.config.startupTimeoutMs}ms`);
  }

  private startBridgeProcess(): void {
    const isWindows = process.platform === "win32";
    const command = this.config.startCommand;
    const args = this.config.startArgs;

    const spawnCommand = isWindows ? "cmd.exe" : command;
    const spawnArgs = isWindows
      ? ["/d", "/s", "/c", command, ...args]
      : args;

    this.startupLogs = [];
    this.child = spawn(spawnCommand, spawnArgs, {
      cwd: this.config.startCwd,
      env: this.buildBridgeEnv(),
      shell: false,
      windowsHide: !this.config.showConsole,
      stdio: this.config.showConsole ? "inherit" : "pipe",
    });

    if (!this.config.showConsole) {
      this.child.stdout?.on("data", (chunk) => {
        this.pushStartupLog(chunk);
      });
      this.child.stderr?.on("data", (chunk) => {
        this.pushStartupLog(chunk);
      });
    }

    this.child.on("exit", () => {
      this.child = undefined;
    });
  }

  private killManagedProcess(): void {
    const child = this.child;
    if (!child || child.killed) {
      this.child = undefined;
      return;
    }

    if (process.platform === "win32" && child.pid) {
      try {
        execFileSync(
          "taskkill",
          ["/PID", String(child.pid), "/T", "/F"],
          {
            stdio: "ignore",
            windowsHide: true,
          },
        );
        this.child = undefined;
        return;
      } catch {
        // Fall through to standard kill as a fallback.
      }
    }

    try {
      child.kill("SIGTERM");
    } catch {
      // Ignore kill errors on shutdown.
    } finally {
      this.child = undefined;
    }
  }

  private pushStartupLog(chunk: unknown): void {
    const text = String(chunk);
    if (!text) {
      return;
    }
    this.startupLogs.push(text);

    if (this.startupLogs.length > 30) {
      this.startupLogs.shift();
    }
  }

  private buildBridgeEnv(): NodeJS.ProcessEnv {
    const env = {
      ...process.env,
    };

    try {
      const url = new URL(this.config.url);
      if (url.port) {
        env.PORT = url.port;
      }
      if (url.hostname) {
        env.HOST = url.hostname;
      }
    } catch {
      // Ignore URL parsing issues and keep current env values.
    }

    return env;
  }
}
