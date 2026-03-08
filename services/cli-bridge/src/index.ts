import "dotenv/config";
import Fastify from "fastify";

import { loadConfig } from "./config";
import { HttpError } from "./errors";
import { SessionManager } from "./bridge/session-manager";
import { AgentId } from "./types";

type JsonObject = Record<string, unknown>;

function asObject(value: unknown, context: string): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, `${context} must be an object`);
  }
  return value as JsonObject;
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

function asAgentId(value: unknown): AgentId {
  const normalized = asString(value, "agentId");
  if (normalized !== "codex" && normalized !== "qwen") {
    throw new HttpError(400, "agentId must be one of: codex, qwen");
  }
  return normalized;
}

async function bootstrap(): Promise<void> {
  const config = loadConfig();
  const manager = new SessionManager(config);

  const app = Fastify({
    logger: true,
  });

  app.get("/health", async () => ({
    ok: true,
    service: "cli-bridge",
    time: new Date().toISOString(),
  }));

  app.get("/agents", async () => ({
    items: manager.listAgents().map((agent) => ({
      id: agent.id,
      title: agent.title,
      command: agent.command,
      args: agent.args,
    })),
  }));

  app.get("/sessions", async () => ({
    items: manager.listSessions(),
  }));

  app.post("/sessions", async (request, reply) => {
    const body = asObject(request.body, "body");
    const created = manager.createSession(
      asAgentId(body.agentId),
      asOptionalString(body.cwd, "cwd"),
    );
    return reply.status(201).send(created);
  });

  app.delete("/sessions/:sessionId", async (request, reply) => {
    const params = asObject(request.params, "params");
    const sessionId = asString(params.sessionId, "sessionId");
    if (!manager.closeSession(sessionId)) {
      throw new HttpError(404, `Session ${sessionId} was not found`);
    }

    return reply.status(204).send();
  });

  app.post("/sessions/:sessionId/prompt", async (request) => {
    const params = asObject(request.params, "params");
    const body = asObject(request.body, "body");

    return manager.runInSession(asString(params.sessionId, "sessionId"), asString(body.prompt, "prompt"), {
      timeoutMs: asOptionalNumber(body.timeoutMs, "timeoutMs"),
      idleMs: asOptionalNumber(body.idleMs, "idleMs"),
    });
  });

  app.post("/runs", async (request, reply) => {
    const body = asObject(request.body, "body");
    const result = await manager.runOnce(asAgentId(body.agentId), asString(body.prompt, "prompt"), {
      cwd: asOptionalString(body.cwd, "cwd"),
      timeoutMs: asOptionalNumber(body.timeoutMs, "timeoutMs"),
      idleMs: asOptionalNumber(body.idleMs, "idleMs"),
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
    manager.closeAll();
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
      agents: manager.listAgents().map((agent) => agent.id),
    },
    "cli-bridge started",
  );
}

bootstrap().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
