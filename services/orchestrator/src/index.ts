import "dotenv/config";
import Fastify from "fastify";

import { ApiRunner } from "./adapters/api-runner";
import { BridgeRunner } from "./adapters/bridge-runner";
import { BridgeSupervisor } from "./bridge/bridge-supervisor";
import { loadConfig } from "./config";
import { HttpError } from "./errors";
import {
  OrchestrationCanceledError,
  runMinimalOrchestration,
} from "./orchestration/minimal-orchestration";
import { TaskStore } from "./tasks/task-store";
import { AgentRunner } from "./types";

type JsonObject = Record<string, unknown>;

function asObject(value: unknown, context: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, `${context} must be an object`);
  }
  return value as JsonObject;
}

function asOptionalObject(value: unknown, context: string): JsonObject | undefined {
  if (value == null) {
    return undefined;
  }
  return asObject(value, context);
}

function asString(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpError(400, `${field} must be a non-empty string`);
  }
  return value.trim();
}

function asOptionalString(value: unknown, field: string): string | undefined {
  if (value == null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new HttpError(400, `${field} must be a string`);
  }
  const normalized = value.trim();
  return normalized ? normalized : undefined;
}

function asOptionalNumber(value: unknown, field: string): number | undefined {
  if (value == null) {
    return undefined;
  }
  if (typeof value !== "number") {
    throw new HttpError(400, `${field} must be a number`);
  }
  return value;
}

function asOptionalInteger(value: unknown, field: string): number | undefined {
  if (value == null) {
    return undefined;
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value) || value <= 0 || !Number.isInteger(value)) {
      throw new HttpError(400, `${field} must be a positive integer`);
    }
    return value;
  }

  if (typeof value === "string") {
    const normalized = value.trim();
    if (!normalized) {
      return undefined;
    }
    const parsed = Number(normalized);
    if (!Number.isFinite(parsed) || parsed <= 0 || !Number.isInteger(parsed)) {
      throw new HttpError(400, `${field} must be a positive integer`);
    }
    return parsed;
  }

  throw new HttpError(400, `${field} must be a positive integer`);
}

function resolveTimeout(
  candidate: number | undefined,
  fallback: number,
  maxTimeoutMs: number,
  field: string,
): number {
  const timeout = candidate ?? fallback;
  if (!Number.isFinite(timeout) || timeout <= 0) {
    throw new HttpError(400, `${field} must be a positive number`);
  }
  if (timeout > maxTimeoutMs) {
    throw new HttpError(
      400,
      `${field} cannot exceed MAX_TIMEOUT_MS (${maxTimeoutMs})`,
    );
  }
  return Math.floor(timeout);
}

async function bootstrap(): Promise<void> {
  const config = loadConfig();
  const bridgeSupervisor =
    config.mode === "bridge" ? new BridgeSupervisor(config.bridge) : undefined;

  let runner: AgentRunner;
  if (config.mode === "bridge") {
    runner = new BridgeRunner({
      baseUrl: config.bridge.url,
      requestTimeoutMs: config.bridge.requestTimeoutMs,
    });
  } else {
    runner = new ApiRunner({
      runUrl: config.api.runUrl,
      requestTimeoutMs: config.api.requestTimeoutMs,
      authHeader: config.api.authHeader,
      authToken: config.api.authToken,
    });
  }

  const app = Fastify({
    logger: true,
  });
  const taskStore = new TaskStore();
  const runningTaskIds = new Set<string>();

  const ensureBridgeReady = async (): Promise<void> => {
    if (!bridgeSupervisor) {
      return;
    }

    try {
      await bridgeSupervisor.ensureReady();
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Bridge startup failed";
      throw new HttpError(502, message);
    }
  };

  const runTaskInBackground = async (taskId: string): Promise<void> => {
    if (runningTaskIds.has(taskId)) {
      return;
    }
    runningTaskIds.add(taskId);

    try {
      const snapshot = taskStore.getTask(taskId);
      if (!snapshot) {
        return;
      }
      if (snapshot.status === "canceled") {
        return;
      }

      try {
        await ensureBridgeReady();
      } catch (error) {
        const message =
          error instanceof Error ? error.message : "Bridge startup failed";
        taskStore.finishFailed(taskId, message);
        return;
      }

      taskStore.markPlanning(taskId);
      const result = await runMinimalOrchestration(runner, {
        task: snapshot.input.task,
        cwd: snapshot.input.cwd,
        managerTimeoutMs: snapshot.input.managerTimeoutMs,
        workerTimeoutMs: snapshot.input.workerTimeoutMs,
        shouldCancel: () => taskStore.shouldCancel(taskId),
        onProgress: (event) => {
          if (event.phase === "workers_started") {
            taskStore.markRunning(taskId);
          }
          taskStore.addProgress(taskId, event);
        },
      });

      taskStore.finishCompleted(taskId, result);
    } catch (error) {
      if (error instanceof OrchestrationCanceledError) {
        taskStore.finishCanceled(taskId);
        return;
      }

      const message = error instanceof Error ? error.message : "Task execution failed";
      taskStore.finishFailed(taskId, message);
    } finally {
      runningTaskIds.delete(taskId);
    }
  };

  app.get("/health", async () => {
    const bridgeStatus = bridgeSupervisor ? await bridgeSupervisor.status() : undefined;
    return {
      ok: true,
      service: "orchestrator",
      mode: config.mode,
      bridge: bridgeStatus,
      runningTasks: runningTaskIds.size,
      time: new Date().toISOString(),
    };
  });

  app.get("/tasks", async (request) => {
    const query = asOptionalObject(request.query, "query") ?? {};
    const limit = asOptionalInteger(query.limit, "limit");
    return {
      items: taskStore.listTasks(limit),
    };
  });

  app.get("/tasks/:taskId", async (request) => {
    const params = asObject(request.params, "params");
    const taskId = asString(params.taskId, "taskId");
    const snapshot = taskStore.getTask(taskId);
    if (!snapshot) {
      throw new HttpError(404, `Task ${taskId} was not found`);
    }
    return snapshot;
  });

  app.post("/tasks/:taskId/cancel", async (request, reply) => {
    const params = asObject(request.params, "params");
    const taskId = asString(params.taskId, "taskId");
    const snapshot = taskStore.requestCancel(taskId);
    if (!snapshot) {
      throw new HttpError(404, `Task ${taskId} was not found`);
    }

    return reply.status(202).send(snapshot);
  });

  app.get("/tasks/:taskId/events", async (request, reply) => {
    const params = asObject(request.params, "params");
    const taskId = asString(params.taskId, "taskId");
    const snapshot = taskStore.getTask(taskId);
    if (!snapshot) {
      throw new HttpError(404, `Task ${taskId} was not found`);
    }

    reply.hijack();
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });

    const send = (eventName: string, data: unknown): void => {
      reply.raw.write(`event: ${eventName}\n`);
      reply.raw.write(`data: ${JSON.stringify(data)}\n\n`);
    };

    send("snapshot", snapshot);
    const unsubscribe = taskStore.subscribe(taskId, (event) => {
      send("task_event", event);
    });

    const keepalive = setInterval(() => {
      if (!reply.raw.writableEnded) {
        reply.raw.write(": keepalive\n\n");
      }
    }, 15_000);

    request.raw.on("close", () => {
      clearInterval(keepalive);
      unsubscribe();
      if (!reply.raw.writableEnded) {
        reply.raw.end();
      }
    });
  });

  app.post("/tasks/minimal", async (request, reply) => {
    const body = asOptionalObject(request.body, "body") ?? {};
    const cwd = asOptionalString(body.cwd, "cwd") ?? config.defaultCwd;
    const managerTimeoutMs = resolveTimeout(
      asOptionalNumber(body.managerTimeoutMs, "managerTimeoutMs"),
      config.managerTimeoutMs,
      config.maxTimeoutMs,
      "managerTimeoutMs",
    );
    const workerTimeoutMs = resolveTimeout(
      asOptionalNumber(body.workerTimeoutMs, "workerTimeoutMs"),
      config.workerTimeoutMs,
      config.maxTimeoutMs,
      "workerTimeoutMs",
    );

    const task = taskStore.createTask({
      task: asOptionalString(body.task, "task"),
      cwd,
      managerTimeoutMs,
      workerTimeoutMs,
    });

    setImmediate(() => {
      void runTaskInBackground(task.id);
    });

    return reply.status(202).send(task);
  });

  app.post("/orchestrations/minimal", async (request, reply) => {
    const body = asOptionalObject(request.body, "body") ?? {};
    const cwd = asOptionalString(body.cwd, "cwd") ?? config.defaultCwd;
    const managerTimeoutMs = resolveTimeout(
      asOptionalNumber(body.managerTimeoutMs, "managerTimeoutMs"),
      config.managerTimeoutMs,
      config.maxTimeoutMs,
      "managerTimeoutMs",
    );
    const workerTimeoutMs = resolveTimeout(
      asOptionalNumber(body.workerTimeoutMs, "workerTimeoutMs"),
      config.workerTimeoutMs,
      config.maxTimeoutMs,
      "workerTimeoutMs",
    );

    await ensureBridgeReady();

    const result = await runMinimalOrchestration(runner, {
      task: asOptionalString(body.task, "task"),
      cwd,
      managerTimeoutMs,
      workerTimeoutMs,
    });

    return reply.status(201).send(result);
  });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof HttpError) {
      return reply.status(error.statusCode).send({
        error: error.message,
      });
    }

    app.log.error(error);
    return reply.status(500).send({
      error: "Internal server error",
    });
  });

  const shutdown = async (): Promise<void> => {
    bridgeSupervisor?.stop();
    await app.close();
  };

  process.on("SIGINT", () => {
    void shutdown();
  });
  process.on("SIGTERM", () => {
    void shutdown();
  });

  await app.listen({
    host: config.host,
    port: config.port,
  });

  app.log.info(
    {
      host: config.host,
      port: config.port,
      mode: config.mode,
      bridgeUrl: config.bridge.url,
      bridgeAutostart: config.bridge.autostart,
    },
    "orchestrator started",
  );
}

bootstrap().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
