import "dotenv/config";
import Fastify from "fastify";

import { ApiRunner } from "./adapters/api-runner";
import { BridgeRunner } from "./adapters/bridge-runner";
import { AuthActor, AuthService } from "./auth/auth";
import { BridgeSupervisor } from "./bridge/bridge-supervisor";
import { loadConfig } from "./config";
import { HttpError } from "./errors";
import { GraphOrchestrator } from "./graphs/graph-orchestrator";
import { GraphStore } from "./graphs/graph-store";
import { GraphNode, GraphUpsertInput, NodeChatMessage } from "./graphs/graph-types";
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

function asObjectArray(value: unknown, field: string): JsonObject[] {
  if (!Array.isArray(value)) {
    throw new HttpError(400, `${field} must be an array`);
  }

  return value.map((item, index) => asObject(item, `${field}[${index}]`));
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

function asOptionalStringArray(value: unknown, field: string): string[] | undefined {
  if (value == null) {
    return undefined;
  }

  if (!Array.isArray(value)) {
    throw new HttpError(400, `${field} must be an array of strings`);
  }

  return value.map((item, index) => asString(item, `${field}[${index}]`));
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

function asOptionalBoolean(value: unknown, field: string): boolean | undefined {
  if (value == null) {
    return undefined;
  }
  if (typeof value !== "boolean") {
    throw new HttpError(400, `${field} must be a boolean`);
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

function asOptionalNonNegativeInteger(value: unknown, field: string): number | undefined {
  if (value == null) {
    return undefined;
  }

  if (typeof value === "number") {
    if (!Number.isFinite(value) || value < 0 || !Number.isInteger(value)) {
      throw new HttpError(400, `${field} must be a non-negative integer`);
    }
    return value;
  }

  if (typeof value === "string") {
    const normalized = value.trim();
    if (!normalized) {
      return undefined;
    }
    const parsed = Number(normalized);
    if (!Number.isFinite(parsed) || parsed < 0 || !Number.isInteger(parsed)) {
      throw new HttpError(400, `${field} must be a non-negative integer`);
    }
    return parsed;
  }

  throw new HttpError(400, `${field} must be a non-negative integer`);
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

function parseGraphUpsertInput(body: JsonObject): GraphUpsertInput {
  const acl = asOptionalObject(body.acl, "acl");

  const nodes = asObjectArray(body.nodes, "nodes").map((node, index) => {
    const position = asOptionalObject(node.position, `nodes[${index}].position`);
    const config = asOptionalObject(node.config, `nodes[${index}].config`);

    return {
      id: asOptionalString(node.id, `nodes[${index}].id`),
      type: asString(node.type, `nodes[${index}].type`) as "manager" | "worker" | "agent",
      label: asString(node.label, `nodes[${index}].label`),
      position: position
        ? {
            x: asOptionalNumber(position.x, `nodes[${index}].position.x`),
            y: asOptionalNumber(position.y, `nodes[${index}].position.y`),
          }
        : undefined,
      config: config
        ? {
            agentId: asOptionalString(config.agentId, `nodes[${index}].config.agentId`) as
              | "codex"
              | "qwen"
              | undefined,
            role: asOptionalString(config.role, `nodes[${index}].config.role`) as
              | "manager"
              | "worker"
              | undefined,
            fullAccess: asOptionalBoolean(
              config.fullAccess,
              `nodes[${index}].config.fullAccess`,
            ),
            prompt: asOptionalString(config.prompt, `nodes[${index}].config.prompt`),
            cwd: asOptionalString(config.cwd, `nodes[${index}].config.cwd`),
            timeoutMs: asOptionalNumber(config.timeoutMs, `nodes[${index}].config.timeoutMs`),
            maxRetries: asOptionalNonNegativeInteger(
              config.maxRetries,
              `nodes[${index}].config.maxRetries`,
            ),
            retryDelayMs: asOptionalInteger(
              config.retryDelayMs,
              `nodes[${index}].config.retryDelayMs`,
            ),
            metadata: asOptionalObject(config.metadata, `nodes[${index}].config.metadata`),
          }
        : undefined,
    };
  });

  const edges = asObjectArray(body.edges, "edges").map((edge, index) => ({
    id: asOptionalString(edge.id, `edges[${index}].id`),
    fromNodeId: asString(edge.fromNodeId, `edges[${index}].fromNodeId`),
    toNodeId: asString(edge.toNodeId, `edges[${index}].toNodeId`),
    relationType: asOptionalString(edge.relationType, `edges[${index}].relationType`) as
      | "manager_to_worker"
      | "dependency"
      | "peer"
      | "feedback"
      | undefined,
  }));

  return {
    name: asString(body.name, "name"),
    description: asOptionalString(body.description, "description"),
    nodes,
    edges,
    acl: acl
      ? {
          editors: asOptionalStringArray(acl.editors, "acl.editors"),
          viewers: asOptionalStringArray(acl.viewers, "acl.viewers"),
        }
      : undefined,
  };
}

function buildNodeChatPrompt(node: GraphNode, history: NodeChatMessage[], message: string): string {
  const parts: string[] = [];

  if (node.config.prompt?.trim()) {
    parts.push(`Node instructions:\n${node.config.prompt.trim()}`);
  } else {
    parts.push(
      `You are node '${node.label}' (${node.id}) in an orchestration graph. Reply concisely and provide actionable output.`,
    );
  }

  const historyTail = history.slice(-6);
  if (historyTail.length > 0) {
    parts.push(
      [
        "Conversation history:",
        ...historyTail.map((item) => `${item.role}: ${item.text}`),
      ].join("\n"),
    );
  }

  parts.push(`User message:\n${message}`);
  return parts.join("\n\n");
}

async function bootstrap(): Promise<void> {
  const config = loadConfig();
  const authService = new AuthService(config.auth);

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
  const graphStore = new GraphStore();
  const graphOrchestrator = new GraphOrchestrator(runner, graphStore, {
    defaultNodeTimeoutMs: config.workerTimeoutMs,
    maxNodeTimeoutMs: config.maxTimeoutMs,
    defaultCwd: config.defaultCwd,
    maxParallelNodes: 8,
  });
  const runningTaskIds = new Set<string>();

  const resolveActor = (request: Parameters<typeof authService.resolveActor>[0]): AuthActor => {
    return authService.resolveActor(request);
  };

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
      authEnabled: config.auth.enabled,
      bridge: bridgeStatus,
      runningTasks: runningTaskIds.size,
      runningGraphRuns: graphOrchestrator.getRunningRunsCount(),
      graphs: graphStore.getGraphsCount(),
      graphRuns: graphStore.getRunsCount(),
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

  app.get("/graphs", async (request) => {
    const actor = resolveActor(request);
    const query = asOptionalObject(request.query, "query") ?? {};
    const limit = asOptionalInteger(query.limit, "limit");

    return {
      items: graphStore.listGraphs(actor, limit),
    };
  });

  app.post("/graphs", async (request, reply) => {
    const actor = resolveActor(request);
    const body = asObject(request.body, "body");

    const graph = graphStore.createGraph(parseGraphUpsertInput(body), actor);
    return reply.status(201).send(graph);
  });

  app.get("/graphs/:id", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const query = asOptionalObject(request.query, "query") ?? {};
    const graphId = asString(params.id, "id");
    const revision = asOptionalInteger(query.revision, "revision");

    const graph = graphStore.getGraph(graphId, actor, revision);
    if (!graph) {
      throw new HttpError(404, `Graph ${graphId} was not found`);
    }

    return graph;
  });

  app.put("/graphs/:id", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const body = asObject(request.body, "body");
    const graphId = asString(params.id, "id");

    const graph = graphStore.updateGraph(graphId, parseGraphUpsertInput(body), actor);
    if (!graph) {
      throw new HttpError(404, `Graph ${graphId} was not found`);
    }

    return graph;
  });

  app.post("/graphs/:id/validate", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const query = asOptionalObject(request.query, "query") ?? {};
    const body = asOptionalObject(request.body, "body") ?? {};
    const graphId = asString(params.id, "id");

    const revision = asOptionalInteger(
      body.graphRevision ?? query.graphRevision,
      "graphRevision",
    );

    return graphStore.validateGraph(graphId, actor, revision);
  });

  app.post("/graphs/:id/runs", async (request, reply) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const body = asOptionalObject(request.body, "body") ?? {};
    const graphId = asString(params.id, "id");

    const graphRevision = asOptionalInteger(body.graphRevision, "graphRevision");
    const kickoffMessage = asOptionalString(body.kickoffMessage, "kickoffMessage");
    const kickoffManagerNodeId = asOptionalString(
      body.kickoffManagerNodeId,
      "kickoffManagerNodeId",
    );

    await ensureBridgeReady();

    const graph = graphStore.getGraph(graphId, actor, graphRevision);
    if (!graph) {
      throw new HttpError(404, `Graph ${graphId} was not found`);
    }

    if (kickoffMessage && !kickoffManagerNodeId) {
      throw new HttpError(
        400,
        "kickoffManagerNodeId is required when kickoffMessage is provided",
      );
    }

    if (kickoffManagerNodeId) {
      const managerNode = graph.revision.nodes.find(
        (node) => node.id === kickoffManagerNodeId,
      );

      if (!managerNode) {
        throw new HttpError(
          400,
          `Node ${kickoffManagerNodeId} not found in graph revision`,
        );
      }

      const isManager =
        managerNode.type === "manager" || managerNode.config.role === "manager";
      if (!isManager) {
        throw new HttpError(
          400,
          `Node ${kickoffManagerNodeId} is not a manager node`,
        );
      }
    }

    const run = graphStore.createRun(graphId, actor, {
      graphRevision,
      kickoffMessage,
      kickoffManagerNodeId,
    });

    if (kickoffMessage && kickoffManagerNodeId) {
      graphStore.addNodeMessage(
        graphId,
        kickoffManagerNodeId,
        "user",
        kickoffMessage,
        run.runId,
      );
      graphStore.addNodeMessage(
        graphId,
        kickoffManagerNodeId,
        "system",
        `Run ${run.runId} started from manager dialog`,
        run.runId,
      );
    }

    graphOrchestrator.startRunInBackground(run.runId);
    return reply.status(202).send(run);
  });

  app.get("/graphs/:id/runs", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const query = asOptionalObject(request.query, "query") ?? {};
    const graphId = asString(params.id, "id");
    const limit = asOptionalInteger(query.limit, "limit");

    return {
      items: graphStore.listGraphRuns(graphId, actor, limit),
    };
  });

  app.get("/graphs/:id/runs/:runId", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const graphId = asString(params.id, "id");
    const runId = asString(params.runId, "runId");

    const run = graphStore.getRun(runId, actor);
    if (!run || run.graphId !== graphId) {
      throw new HttpError(404, `Run ${runId} was not found for graph ${graphId}`);
    }

    return run;
  });

  app.get("/graph-runs/:runId", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const runId = asString(params.runId, "runId");

    const run = graphStore.getRun(runId, actor);
    if (!run) {
      throw new HttpError(404, `Run ${runId} was not found`);
    }

    return run;
  });

  app.post("/graph-runs/:runId/cancel", async (request, reply) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const runId = asString(params.runId, "runId");

    const run = graphStore.requestRunCancel(runId, actor);
    if (!run) {
      throw new HttpError(404, `Run ${runId} was not found`);
    }

    return reply.status(202).send(run);
  });

  app.get("/graph-runs/:runId/events", async (request, reply) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const runId = asString(params.runId, "runId");
    const run = graphStore.getRun(runId, actor);
    if (!run) {
      throw new HttpError(404, `Run ${runId} was not found`);
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

    send("snapshot", run);
    const unsubscribe = graphStore.subscribeRun(runId, (event) => {
      send("run_event", event);
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

  app.post("/nodes/:nodeId/chat", async (request, reply) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const body = asObject(request.body, "body");

    const nodeId = asString(params.nodeId, "nodeId");
    const graphId = asOptionalString(body.graphId, "graphId");
    const runId = asOptionalString(body.runId, "runId");
    const message = asString(body.message, "message");
    const timeoutCandidate = asOptionalNumber(body.timeoutMs, "timeoutMs");
    const cwd = asOptionalString(body.cwd, "cwd");

    const resolvedNode = graphStore.resolveNode(nodeId, actor, graphId);
    if (runId) {
      const run = graphStore.getRun(runId, actor);
      if (!run) {
        throw new HttpError(404, `Run ${runId} was not found`);
      }

      if (run.graphId !== resolvedNode.graphId) {
        throw new HttpError(400, `Run ${runId} does not belong to graph ${resolvedNode.graphId}`);
      }

      if (!run.nodeStates[nodeId]) {
        throw new HttpError(400, `Node ${nodeId} is not part of run ${runId}`);
      }
    }

    const history = graphStore.listNodeMessages(nodeId, actor, resolvedNode.graphId, 20);
    const userMessage = graphStore.addNodeMessage(
      resolvedNode.graphId,
      nodeId,
      "user",
      message,
      runId,
    );

    const timeoutMs = resolveTimeout(
      timeoutCandidate,
      resolvedNode.node.config.timeoutMs ?? config.workerTimeoutMs,
      config.maxTimeoutMs,
      "timeoutMs",
    );

    const prompt = buildNodeChatPrompt(resolvedNode.node, history, message);

    try {
      await ensureBridgeReady();

      const result = await runner.run(resolvedNode.node.config.agentId, prompt, {
        cwd: cwd ?? resolvedNode.node.config.cwd ?? config.defaultCwd,
        timeoutMs,
        fullAccess: resolvedNode.node.config.fullAccess === true,
      });

      if (runId) {
        graphStore.appendNodeLog(runId, nodeId, "stdout", result.output);
      } else {
        graphStore.appendStandaloneNodeLog(
          resolvedNode.graphId,
          nodeId,
          "stdout",
          result.output,
          runId,
        );
      }

      const assistantMessage = graphStore.addNodeMessage(
        resolvedNode.graphId,
        nodeId,
        "assistant",
        result.output,
        runId,
      );

      return reply.status(201).send({
        userMessage,
        assistantMessage,
        result,
      });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : "Node chat failed";

      if (runId) {
        graphStore.appendNodeLog(runId, nodeId, "stderr", errorMessage);
      } else {
        graphStore.appendStandaloneNodeLog(
          resolvedNode.graphId,
          nodeId,
          "stderr",
          errorMessage,
          runId,
        );
      }

      graphStore.addNodeMessage(
        resolvedNode.graphId,
        nodeId,
        "system",
        `Node chat error: ${errorMessage}`,
        runId,
      );

      throw error;
    }
  });

  app.get("/nodes/:nodeId/messages", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const query = asOptionalObject(request.query, "query") ?? {};

    const nodeId = asString(params.nodeId, "nodeId");
    const graphId = asOptionalString(query.graphId, "graphId");
    const limit = asOptionalInteger(query.limit, "limit");

    return {
      items: graphStore.listNodeMessages(nodeId, actor, graphId, limit),
    };
  });

  app.get("/nodes/:nodeId/logs", async (request) => {
    const actor = resolveActor(request);
    const params = asObject(request.params, "params");
    const query = asOptionalObject(request.query, "query") ?? {};

    const nodeId = asString(params.nodeId, "nodeId");
    const graphId = asOptionalString(query.graphId, "graphId");
    const runId = asOptionalString(query.runId, "runId");
    const limit = asOptionalInteger(query.limit, "limit");

    return {
      items: graphStore.listNodeLogs(nodeId, actor, {
        graphId,
        runId,
        limit,
      }),
    };
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
      authEnabled: config.auth.enabled,
    },
    "orchestrator started",
  );
}

bootstrap().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
