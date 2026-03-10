import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { AuthActor } from "../auth/auth";
import { HttpError } from "../errors";
import { RunResult } from "../types";
import {
  GraphEdge,
  GraphNode,
  GraphRun,
  GraphRunEvent,
  GraphRunNodeState,
  GraphRunStatus,
  GraphRunStreamEvent,
  GraphUpsertInput,
  ManagerTraceEntry,
  NodeArtifacts,
  NodeAttemptRecord,
  NodeChatMessage,
  NodeLogEntry,
  NodeLogStream,
  NodeMessageRole,
  OrchestrationGraph,
  ResolvedGraphNode,
} from "./graph-types";
import { validateGraph } from "./graph-validator";

const MAX_RUN_EVENTS = 1_500;
const MAX_NODE_MESSAGES = 500;
const MAX_NODE_LOGS = 2_000;
const SNAPSHOT_VERSION = 2;

interface GraphRecord {
  id: string;
  name: string;
  description?: string;
  ownerId: string;
  acl: {
    editors: string[];
    viewers: string[];
  };
  createdAt: string;
  updatedAt: string;
  latestRevision: number;
  revisions: Map<number, { createdAt: string; createdBy: string; nodes: GraphNode[]; edges: GraphEdge[] }>;
}

interface GraphRunRecord extends GraphRun {
  nextEventSequence: number;
  nextNodeLogSequence: number;
}

interface NormalizedGraphUpsertInput {
  name: string;
  description?: string;
  nodes: GraphNode[];
  edges: GraphEdge[];
  acl?: {
    editors?: string[];
    viewers?: string[];
  };
}

interface PersistedGraphRecord {
  id: string;
  name: string;
  description?: string;
  ownerId: string;
  acl: {
    editors: string[];
    viewers: string[];
  };
  createdAt: string;
  updatedAt: string;
  latestRevision: number;
  revisions: Array<{
    revision: number;
    createdAt: string;
    createdBy: string;
    nodes: GraphNode[];
    edges: GraphEdge[];
  }>;
}

export interface PersistedGraphStoreSnapshot {
  version: number;
  savedAt: string;
  graphs: PersistedGraphRecord[];
  runs: GraphRunRecord[];
  nodeMessages: Array<{ key: string; items: NodeChatMessage[] }>;
  nodeLogs: Array<{ key: string; items: NodeLogEntry[] }>;
  nodeAttempts: NodeAttemptRecord[];
}

interface NodeAttemptClaim {
  record: NodeAttemptRecord;
  isNewClaim: boolean;
}

export interface GraphStoreOptions {
  persistenceFilePath?: string;
  maxRunEvents?: number;
  maxNodeMessages?: number;
  maxNodeLogs?: number;
  initialSnapshot?: PersistedGraphStoreSnapshot;
  onPersistSnapshot?: (snapshot: PersistedGraphStoreSnapshot) => void;
}

export interface CreateRunOptions {
  graphRevision?: number;
  kickoffMessage?: string;
  kickoffManagerNodeId?: string;
  cwd?: string;
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function uniqueStrings(input: string[]): string[] {
  return [...new Set(input.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim()))];
}

function assertPositiveInteger(value: number | undefined, field: string): number | undefined {
  if (value == null) {
    return undefined;
  }

  if (!Number.isFinite(value) || value <= 0 || !Number.isInteger(value)) {
    throw new HttpError(400, `${field} must be a positive integer`);
  }

  return value;
}

function assertNonNegativeInteger(value: number | undefined, field: string): number | undefined {
  if (value == null) {
    return undefined;
  }

  if (!Number.isFinite(value) || value < 0 || !Number.isInteger(value)) {
    throw new HttpError(400, `${field} must be a non-negative integer`);
  }

  return value;
}

function assertObject(value: unknown, field: string): Record<string, unknown> | undefined {
  if (value == null) {
    return undefined;
  }

  if (typeof value !== "object" || Array.isArray(value)) {
    throw new HttpError(400, `${field} must be an object`);
  }

  return value as Record<string, unknown>;
}

function assertBoolean(value: unknown, field: string): boolean | undefined {
  if (value == null) {
    return undefined;
  }
  if (typeof value !== "boolean") {
    throw new HttpError(400, `${field} must be a boolean`);
  }
  return value;
}

function isTerminalNodeStatus(status: GraphRunNodeState["status"]): boolean {
  return (
    status === "completed" ||
    status === "failed" ||
    status === "canceled" ||
    status === "skipped"
  );
}

function normalizeChunk(chunk: string): string {
  return chunk.replace(/\r/g, "").trimEnd();
}

function ensureNonNegativeInteger(value: unknown, fallback: number): number {
  if (typeof value !== "number") {
    return fallback;
  }

  if (!Number.isFinite(value) || value < 0 || !Number.isInteger(value)) {
    return fallback;
  }

  return value;
}

export class GraphStore {
  private readonly graphs = new Map<string, GraphRecord>();
  private readonly runs = new Map<string, GraphRunRecord>();
  private readonly nodeMessages = new Map<string, NodeChatMessage[]>();
  private readonly nodeLogs = new Map<string, NodeLogEntry[]>();
  private readonly nodeAttempts = new Map<string, NodeAttemptRecord>();
  private readonly emitter = new EventEmitter();

  private readonly maxRunEvents: number;
  private readonly maxNodeMessages: number;
  private readonly maxNodeLogs: number;
  private readonly persistenceFilePath?: string;
  private readonly onPersistSnapshot?: (snapshot: PersistedGraphStoreSnapshot) => void;

  constructor(options: GraphStoreOptions = {}) {
    this.maxRunEvents = Math.max(50, options.maxRunEvents ?? MAX_RUN_EVENTS);
    this.maxNodeMessages = Math.max(50, options.maxNodeMessages ?? MAX_NODE_MESSAGES);
    this.maxNodeLogs = Math.max(100, options.maxNodeLogs ?? MAX_NODE_LOGS);
    this.persistenceFilePath = options.persistenceFilePath?.trim() || undefined;
    this.onPersistSnapshot = options.onPersistSnapshot;

    if (options.initialSnapshot) {
      this.applySnapshot(options.initialSnapshot);
      return;
    }

    this.loadFromDisk();
  }

  getGraphsCount(): number {
    return this.graphs.size;
  }

  getRunsCount(): number {
    return this.runs.size;
  }

  exportSnapshot(): PersistedGraphStoreSnapshot {
    return this.buildSnapshot();
  }

  listRecoverableRunIds(limit = 100): string[] {
    const clampedLimit = Math.max(1, Math.min(limit, 1_000));
    return [...this.runs.values()]
      .filter((run) => run.status === "queued" || run.status === "running")
      .sort((a, b) => a.updatedAt.localeCompare(b.updatedAt))
      .slice(0, clampedLimit)
      .map((run) => run.runId);
  }

  recoverRunForExecution(runId: string): GraphRun | undefined {
    const run = this.runs.get(runId);
    if (!run) {
      return undefined;
    }

    if (run.status !== "queued" && run.status !== "running") {
      return this.toRunSnapshot(run);
    }

    const recoveredNodeIds: string[] = [];
    for (const state of Object.values(run.nodeStates)) {
      if (state.status !== "running" && state.status !== "retrying") {
        continue;
      }

      state.status = "ready";
      state.finishedAt = undefined;
      state.lastError = "Recovered after orchestrator restart";
      recoveredNodeIds.push(state.nodeId);

      this.pushRunEvent(run, "node_status_changed", {
        nodeId: state.nodeId,
        status: state.status,
        attempts: state.attempts,
        recovered: true,
      });
    }

    if (run.status === "running" || recoveredNodeIds.length > 0) {
      run.updatedAt = new Date().toISOString();
      this.pushRunEvent(run, "graph_run_resumed", {
        recoveredNodeIds,
        status: run.status,
        cancelRequested: run.cancelRequested,
      });
      this.persistState();
    }

    return this.toRunSnapshot(run);
  }

  listGraphs(actor: AuthActor, limit = 50): OrchestrationGraph[] {
    const clampedLimit = Math.max(1, Math.min(limit, 200));
    return [...this.graphs.values()]
      .filter((graph) => this.canRead(actor, graph))
      .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
      .slice(0, clampedLimit)
      .map((record) => this.toGraphSnapshot(record, record.latestRevision));
  }

  createGraph(input: GraphUpsertInput, actor: AuthActor): OrchestrationGraph {
    const now = new Date().toISOString();
    const id = randomUUID();
    const normalized = this.normalizeUpsertInput(input, 1);

    const record: GraphRecord = {
      id,
      name: normalized.name,
      description: normalized.description,
      ownerId: actor.userId,
      acl: {
        editors: uniqueStrings(normalized.acl?.editors ?? []),
        viewers: uniqueStrings(normalized.acl?.viewers ?? []),
      },
      createdAt: now,
      updatedAt: now,
      latestRevision: 1,
      revisions: new Map([
        [
          1,
          {
            createdAt: now,
            createdBy: actor.userId,
            nodes: normalized.nodes,
            edges: normalized.edges,
          },
        ],
      ]),
    };

    this.graphs.set(id, record);
    this.persistState();
    return this.toGraphSnapshot(record, record.latestRevision);
  }

  getGraph(graphId: string, actor: AuthActor, revision?: number): OrchestrationGraph | undefined {
    const record = this.graphs.get(graphId);
    if (!record) {
      return undefined;
    }
    this.assertReadable(actor, record);

    const resolvedRevision = revision ?? record.latestRevision;
    if (!record.revisions.has(resolvedRevision)) {
      throw new HttpError(404, `Revision ${resolvedRevision} for graph ${graphId} was not found`);
    }

    return this.toGraphSnapshot(record, resolvedRevision);
  }

  updateGraph(graphId: string, input: GraphUpsertInput, actor: AuthActor): OrchestrationGraph | undefined {
    const record = this.graphs.get(graphId);
    if (!record) {
      return undefined;
    }
    this.assertWritable(actor, record);

    const nextRevision = record.latestRevision + 1;
    const normalized = this.normalizeUpsertInput(input, nextRevision);

    record.name = normalized.name;
    record.description = normalized.description;
    record.updatedAt = new Date().toISOString();
    record.latestRevision = nextRevision;
    if (normalized.acl) {
      record.acl.editors = uniqueStrings(normalized.acl.editors ?? record.acl.editors);
      record.acl.viewers = uniqueStrings(normalized.acl.viewers ?? record.acl.viewers);
    }

    record.revisions.set(nextRevision, {
      createdAt: record.updatedAt,
      createdBy: actor.userId,
      nodes: normalized.nodes,
      edges: normalized.edges,
    });

    this.persistState();
    return this.toGraphSnapshot(record, nextRevision);
  }

  validateGraph(graphId: string, actor: AuthActor, revision?: number) {
    const graph = this.getGraph(graphId, actor, revision);
    if (!graph) {
      throw new HttpError(404, `Graph ${graphId} was not found`);
    }

    return validateGraph(graph.revision.nodes, graph.revision.edges);
  }

  createRun(graphId: string, actor: AuthActor, options: CreateRunOptions = {}): GraphRun {
    const record = this.graphs.get(graphId);
    if (!record) {
      throw new HttpError(404, `Graph ${graphId} was not found`);
    }

    this.assertWritable(actor, record);

    const graphRevision = options.graphRevision ?? record.latestRevision;
    const revision = record.revisions.get(graphRevision);
    if (!revision) {
      throw new HttpError(404, `Revision ${graphRevision} for graph ${graphId} was not found`);
    }

    const runId = randomUUID();
    const now = new Date().toISOString();

    const nodeStates: Record<string, GraphRunNodeState> = {};
    for (const node of revision.nodes) {
      nodeStates[node.id] = {
        nodeId: node.id,
        status: "pending",
        attempts: 0,
      };
    }

    const run: GraphRunRecord = {
      runId,
      graphId,
      graphRevision,
      cwd: options.cwd?.trim() || undefined,
      kickoffMessage: options.kickoffMessage?.trim() || undefined,
      kickoffManagerNodeId: options.kickoffManagerNodeId?.trim() || undefined,
      requestedBy: actor.userId,
      status: "queued",
      cancelRequested: false,
      createdAt: now,
      updatedAt: now,
      nodes: clone(revision.nodes),
      edges: clone(revision.edges),
      nodeStates,
      managerTrace: [],
      events: [],
      nextEventSequence: 1,
      nextNodeLogSequence: 1,
    };

    this.runs.set(runId, run);
    this.persistState();
    return this.toRunSnapshot(run);
  }

  listGraphRuns(graphId: string, actor: AuthActor, limit = 50): GraphRun[] {
    const graph = this.graphs.get(graphId);
    if (!graph) {
      throw new HttpError(404, `Graph ${graphId} was not found`);
    }
    this.assertReadable(actor, graph);

    const clampedLimit = Math.max(1, Math.min(limit, 200));
    return [...this.runs.values()]
      .filter((run) => run.graphId === graphId)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .slice(0, clampedLimit)
      .map((run) => this.toRunSnapshot(run));
  }

  listRunEvents(
    runId: string,
    actor: AuthActor,
    options: {
      afterSequence?: number;
      limit?: number;
    } = {},
  ): GraphRunEvent[] {
    const run = this.runs.get(runId);
    if (!run) {
      throw new HttpError(404, `Run ${runId} was not found`);
    }

    const graph = this.graphs.get(run.graphId);
    if (!graph) {
      throw new HttpError(500, `Graph ${run.graphId} for run ${runId} is missing`);
    }

    this.assertReadable(actor, graph);

    const clampedLimit = Math.max(1, Math.min(options.limit ?? 500, 5_000));
    const afterSequence = Math.max(0, options.afterSequence ?? 0);

    return run.events
      .filter((event) => event.sequence > afterSequence)
      .sort((a, b) => a.sequence - b.sequence)
      .slice(0, clampedLimit)
      .map((event) => clone(event));
  }

  getRun(runId: string, actor: AuthActor): GraphRun | undefined {
    const run = this.runs.get(runId);
    if (!run) {
      return undefined;
    }

    const graph = this.graphs.get(run.graphId);
    if (!graph) {
      throw new HttpError(500, `Graph ${run.graphId} for run ${runId} is missing`);
    }

    this.assertReadable(actor, graph);
    return this.toRunSnapshot(run);
  }

  getRunForExecution(runId: string): GraphRun | undefined {
    const run = this.runs.get(runId);
    return run ? this.toRunSnapshot(run) : undefined;
  }

  requestRunCancel(runId: string, actor: AuthActor): GraphRun | undefined {
    const run = this.runs.get(runId);
    if (!run) {
      return undefined;
    }

    const graph = this.graphs.get(run.graphId);
    if (!graph) {
      throw new HttpError(500, `Graph ${run.graphId} for run ${runId} is missing`);
    }

    this.assertWritable(actor, graph);
    run.cancelRequested = true;
    run.updatedAt = new Date().toISOString();

    if (run.status === "queued") {
      this.markRunFinished(runId, "canceled", "Canceled before start");
    }

    this.persistState();
    return this.toRunSnapshot(run);
  }

  isRunCancelRequested(runId: string): boolean {
    return Boolean(this.runs.get(runId)?.cancelRequested);
  }

  markRunStarted(runId: string): void {
    const run = this.getRunRequired(runId);
    if (run.status !== "queued") {
      return;
    }

    const now = new Date().toISOString();
    run.status = "running";
    run.startedAt = run.startedAt ?? now;
    run.updatedAt = now;

    this.pushRunEvent(run, "graph_run_started", {
      requestedBy: run.requestedBy,
      nodes: run.nodes.length,
      edges: run.edges.length,
      cwd: run.cwd,
    });
    this.persistState();
  }

  markRunFinished(runId: string, status: GraphRunStatus, error?: string): void {
    const run = this.getRunRequired(runId);
    run.status = status;
    run.error = error;
    run.finishedAt = new Date().toISOString();
    run.updatedAt = run.finishedAt;

    this.pushRunEvent(run, "graph_run_finished", {
      status,
      error,
      cancelRequested: run.cancelRequested,
    });
    this.persistState();
  }

  setNodeStatus(
    runId: string,
    nodeId: string,
    status: GraphRunNodeState["status"],
    patch: Partial<GraphRunNodeState> = {},
  ): void {
    const run = this.getRunRequired(runId);
    const state = run.nodeStates[nodeId];
    if (!state) {
      throw new HttpError(404, `Node ${nodeId} for run ${runId} was not found`);
    }

    const now = new Date().toISOString();
    state.status = status;
    state.attempts = patch.attempts ?? state.attempts;

    if (patch.startedAt !== undefined) {
      state.startedAt = patch.startedAt;
    } else if (!state.startedAt && (status === "running" || status === "retrying")) {
      state.startedAt = now;
    }

    if (patch.lastPrompt !== undefined) {
      state.lastPrompt = patch.lastPrompt;
    }

    if (patch.lastAttemptKey !== undefined) {
      state.lastAttemptKey = patch.lastAttemptKey;
    }

    if (patch.summary !== undefined) {
      state.summary = patch.summary;
    }

    if (patch.finishedAt !== undefined) {
      state.finishedAt = patch.finishedAt;
    } else if (isTerminalNodeStatus(status)) {
      state.finishedAt = now;
    }

    if (patch.lastError !== undefined) {
      state.lastError = patch.lastError;
    }

    if (patch.result !== undefined) {
      state.result = patch.result;
    }

    if (patch.artifacts !== undefined) {
      state.artifacts = patch.artifacts;
    }

    run.updatedAt = now;

    this.pushRunEvent(run, "node_status_changed", {
      nodeId,
      status,
      attempts: state.attempts,
      lastError: state.lastError,
      lastPrompt: state.lastPrompt,
      lastAttemptKey: state.lastAttemptKey,
      summary: state.summary,
    });

    if (status === "completed" || status === "failed" || status === "canceled") {
      this.updateManagerTraceConfirmationByWorker(runId, nodeId, status);
    }
    this.persistState();
  }

  setNodeResult(runId: string, nodeId: string, result: RunResult, artifacts: NodeArtifacts): void {
    const run = this.getRunRequired(runId);
    const state = run.nodeStates[nodeId];
    if (!state) {
      throw new HttpError(404, `Node ${nodeId} for run ${runId} was not found`);
    }

    state.result = result;
    state.artifacts = artifacts;
    state.summary = this.buildNodeSummary(result.output);
    state.status = "completed";
    state.finishedAt = new Date().toISOString();
    run.updatedAt = state.finishedAt;

    this.pushRunEvent(run, "node_result_ready", {
      nodeId,
      timedOut: result.timedOut,
      durationMs: result.durationMs,
      summary: state.summary,
      artifacts: {
        hasDiffPatch: Boolean(artifacts.diffPatch),
        stdout: artifacts.stdout?.length ?? 0,
        stderr: artifacts.stderr?.length ?? 0,
        resultFiles: artifacts.resultFiles,
      },
    });

    this.pushRunEvent(run, "node_status_changed", {
      nodeId,
      status: "completed",
      attempts: state.attempts,
      summary: state.summary,
      resultFiles: artifacts.resultFiles,
    });

    this.updateManagerTraceConfirmationByWorker(runId, nodeId, "completed");
    this.persistState();
  }

  appendNodeLog(runId: string, nodeId: string, stream: NodeLogStream, chunk: string): NodeLogEntry {
    const run = this.getRunRequired(runId);
    const state = run.nodeStates[nodeId];
    if (!state) {
      throw new HttpError(404, `Node ${nodeId} for run ${runId} was not found`);
    }

    const normalizedChunk = normalizeChunk(chunk);
    const entry: NodeLogEntry = {
      id: randomUUID(),
      graphId: run.graphId,
      nodeId,
      runId,
      stream,
      chunk: normalizedChunk,
      sequence: run.nextNodeLogSequence,
      createdAt: new Date().toISOString(),
    };

    run.nextNodeLogSequence += 1;
    run.updatedAt = entry.createdAt;

    const bucketKey = this.getNodeBucketKey(run.graphId, nodeId);
    const bucket = this.nodeLogs.get(bucketKey) ?? [];
    bucket.push(entry);
    if (bucket.length > this.maxNodeLogs) {
      bucket.splice(0, bucket.length - this.maxNodeLogs);
    }
    this.nodeLogs.set(bucketKey, bucket);

    this.pushRunEvent(run, "node_log_chunk", {
      nodeId,
      stream,
      sequence: entry.sequence,
      chunk: normalizedChunk,
    });

    this.persistState();
    return clone(entry);
  }

  appendStandaloneNodeLog(
    graphId: string,
    nodeId: string,
    stream: NodeLogStream,
    chunk: string,
    runId?: string,
  ): NodeLogEntry {
    if (!this.graphs.has(graphId)) {
      throw new HttpError(404, `Graph ${graphId} was not found`);
    }

    const normalizedChunk = normalizeChunk(chunk);
    const bucketKey = this.getNodeBucketKey(graphId, nodeId);
    const bucket = this.nodeLogs.get(bucketKey) ?? [];
    const sequence = (bucket.at(-1)?.sequence ?? 0) + 1;

    const entry: NodeLogEntry = {
      id: randomUUID(),
      graphId,
      nodeId,
      runId,
      stream,
      chunk: normalizedChunk,
      sequence,
      createdAt: new Date().toISOString(),
    };

    bucket.push(entry);
    if (bucket.length > this.maxNodeLogs) {
      bucket.splice(0, bucket.length - this.maxNodeLogs);
    }
    this.nodeLogs.set(bucketKey, bucket);
    this.persistState();

    return clone(entry);
  }

  claimNodeAttempt(
    runId: string,
    nodeId: string,
    attempt: number,
    attemptKey: string,
  ): NodeAttemptClaim {
    const run = this.getRunRequired(runId);
    const existing = this.nodeAttempts.get(attemptKey);
    if (existing) {
      if (existing.runId !== runId || existing.nodeId !== nodeId) {
        throw new HttpError(
          409,
          `Attempt key collision for ${attemptKey}: expected ${runId}/${nodeId}, got ${existing.runId}/${existing.nodeId}`,
        );
      }

      if (existing.status === "claimed") {
        const claimedAt = Date.parse(existing.updatedAt);
        if (Number.isFinite(claimedAt) && Date.now() - claimedAt < 30_000) {
          return {
            record: clone(existing),
            isNewClaim: false,
          };
        }

        existing.updatedAt = new Date().toISOString();
        this.persistState();
        return {
          record: clone(existing),
          isNewClaim: true,
        };
      }

      return {
        record: clone(existing),
        isNewClaim: false,
      };
    }

    const now = new Date().toISOString();
    const record: NodeAttemptRecord = {
      attemptKey,
      runId,
      graphId: run.graphId,
      nodeId,
      attempt,
      status: "claimed",
      createdAt: now,
      updatedAt: now,
    };

    this.nodeAttempts.set(attemptKey, record);
    this.persistState();

    return {
      record: clone(record),
      isNewClaim: true,
    };
  }

  completeNodeAttempt(attemptKey: string, result: RunResult, artifacts: NodeArtifacts): NodeAttemptRecord {
    const record = this.getNodeAttemptRequired(attemptKey);
    record.status = "completed";
    record.result = result;
    record.artifacts = artifacts;
    record.error = undefined;
    record.updatedAt = new Date().toISOString();
    this.persistState();

    return clone(record);
  }

  failNodeAttempt(attemptKey: string, error: string): NodeAttemptRecord {
    const record = this.getNodeAttemptRequired(attemptKey);
    record.status = "failed";
    record.error = error;
    record.result = undefined;
    record.artifacts = undefined;
    record.updatedAt = new Date().toISOString();
    this.persistState();

    return clone(record);
  }

  cancelNodeAttempt(attemptKey: string, error?: string): NodeAttemptRecord {
    const record = this.getNodeAttemptRequired(attemptKey);
    record.status = "canceled";
    record.error = error;
    record.result = undefined;
    record.artifacts = undefined;
    record.updatedAt = new Date().toISOString();
    this.persistState();

    return clone(record);
  }

  getNodeAttempt(attemptKey: string): NodeAttemptRecord | undefined {
    const record = this.nodeAttempts.get(attemptKey);
    return record ? clone(record) : undefined;
  }

  addManagerTraceEntry(
    runId: string,
    entry: Omit<ManagerTraceEntry, "id" | "assignedAt" | "runId" | "confirmationStatus">,
  ): ManagerTraceEntry {
    const run = this.getRunRequired(runId);
    const trace: ManagerTraceEntry = {
      id: randomUUID(),
      runId,
      managerNodeId: entry.managerNodeId,
      workerNodeId: entry.workerNodeId,
      task: entry.task,
      reason: entry.reason,
      confirmationStatus: "pending",
      assignedAt: new Date().toISOString(),
      note: entry.note,
    };

    run.managerTrace.push(trace);
    run.updatedAt = trace.assignedAt;
    this.persistState();
    return clone(trace);
  }

  updateManagerTraceConfirmationByWorker(
    runId: string,
    workerNodeId: string,
    status: "completed" | "failed" | "canceled",
    note?: string,
  ): void {
    const run = this.getRunRequired(runId);
    const confirmationStatus = status === "completed" ? "confirmed" : "failed";
    const now = new Date().toISOString();
    let changed = false;

    for (const item of run.managerTrace) {
      if (item.workerNodeId !== workerNodeId || item.confirmationStatus !== "pending") {
        continue;
      }

      item.confirmationStatus = confirmationStatus;
      item.confirmedAt = now;
      item.note = note ?? item.note;
      changed = true;
    }

    if (changed) {
      run.updatedAt = now;
      this.persistState();
    }
  }

  subscribeRun(runId: string, listener: (event: GraphRunStreamEvent) => void): () => void {
    const channel = this.getRunChannel(runId);
    this.emitter.on(channel, listener);
    return () => {
      this.emitter.off(channel, listener);
    };
  }

  resolveNode(nodeId: string, actor: AuthActor, graphId?: string): ResolvedGraphNode {
    if (graphId) {
      const graph = this.graphs.get(graphId);
      if (!graph) {
        throw new HttpError(404, `Graph ${graphId} was not found`);
      }
      this.assertReadable(actor, graph);

      const revision = graph.revisions.get(graph.latestRevision);
      if (!revision) {
        throw new HttpError(500, `Latest revision for graph ${graphId} was not found`);
      }

      const node = revision.nodes.find((candidate) => candidate.id === nodeId);
      if (!node) {
        throw new HttpError(404, `Node ${nodeId} was not found in graph ${graphId}`);
      }

      return {
        graphId,
        graphRevision: graph.latestRevision,
        node: clone(node),
      };
    }

    const hits: ResolvedGraphNode[] = [];
    for (const graph of this.graphs.values()) {
      if (!this.canRead(actor, graph)) {
        continue;
      }

      const revision = graph.revisions.get(graph.latestRevision);
      if (!revision) {
        continue;
      }

      const node = revision.nodes.find((candidate) => candidate.id === nodeId);
      if (node) {
        hits.push({
          graphId: graph.id,
          graphRevision: graph.latestRevision,
          node: clone(node),
        });
      }
    }

    if (hits.length === 0) {
      throw new HttpError(404, `Node ${nodeId} was not found`);
    }

    if (hits.length > 1) {
      throw new HttpError(409, `Node ${nodeId} exists in multiple graphs. Specify graphId.`);
    }

    return hits[0];
  }

  addNodeMessage(
    graphId: string,
    nodeId: string,
    role: NodeMessageRole,
    text: string,
    runId?: string,
  ): NodeChatMessage {
    const message: NodeChatMessage = {
      id: randomUUID(),
      graphId,
      nodeId,
      runId,
      role,
      text,
      createdAt: new Date().toISOString(),
    };

    const bucketKey = this.getNodeBucketKey(graphId, nodeId);
    const bucket = this.nodeMessages.get(bucketKey) ?? [];
    bucket.push(message);
    if (bucket.length > this.maxNodeMessages) {
      bucket.splice(0, bucket.length - this.maxNodeMessages);
    }
    this.nodeMessages.set(bucketKey, bucket);
    this.persistState();

    return clone(message);
  }

  listNodeMessages(nodeId: string, actor: AuthActor, graphId?: string, limit = 100): NodeChatMessage[] {
    const clampedLimit = Math.max(1, Math.min(limit, 500));
    const buckets = this.getNodeBuckets(this.nodeMessages, nodeId, graphId);
    return buckets
      .flatMap((items) => items)
      .filter((message) => {
        const graph = this.graphs.get(message.graphId);
        return Boolean(graph && this.canRead(actor, graph));
      })
      .sort((a, b) => a.createdAt.localeCompare(b.createdAt))
      .slice(-clampedLimit)
      .map((item) => clone(item));
  }

  listNodeLogs(
    nodeId: string,
    actor: AuthActor,
    options: {
      graphId?: string;
      runId?: string;
      limit?: number;
      afterSequence?: number;
    } = {},
  ): NodeLogEntry[] {
    const clampedLimit = Math.max(1, Math.min(options.limit ?? 200, 2_000));
    const afterSequence = options.afterSequence != null
      ? Math.max(0, options.afterSequence)
      : undefined;
    const buckets = this.getNodeBuckets(this.nodeLogs, nodeId, options.graphId);
    const entries = buckets
      .flatMap((items) => items)
      .filter((entry) => {
        if (options.graphId && entry.graphId !== options.graphId) {
          return false;
        }

        if (options.runId && entry.runId !== options.runId) {
          return false;
        }

        if (afterSequence != null && entry.sequence <= afterSequence) {
          return false;
        }

        const graph = this.graphs.get(entry.graphId);
        return Boolean(graph && this.canRead(actor, graph));
      })
      .sort((a, b) => a.sequence - b.sequence);

    if (afterSequence != null) {
      return entries.slice(0, clampedLimit).map((item) => clone(item));
    }

    return entries.slice(-clampedLimit).map((item) => clone(item));
  }

  private normalizeUpsertInput(
    input: GraphUpsertInput,
    revisionHint: number,
  ): NormalizedGraphUpsertInput {
    const name = (input.name ?? "").trim();
    if (!name) {
      throw new HttpError(400, "name must be a non-empty string");
    }

    const nodeIds = new Set<string>();
    const nodes = input.nodes.map((node, index): GraphNode => {
      if (!node || typeof node !== "object") {
        throw new HttpError(400, `nodes[${index}] must be an object`);
      }

      const id = node.id?.trim() || randomUUID();
      if (nodeIds.has(id)) {
        throw new HttpError(400, `Duplicate node id: ${id}`);
      }
      nodeIds.add(id);

      if (node.type !== "manager" && node.type !== "worker" && node.type !== "agent") {
        throw new HttpError(400, `nodes[${index}].type must be manager, worker or agent`);
      }

      const label = node.label?.trim();
      if (!label) {
        throw new HttpError(400, `nodes[${index}].label must be a non-empty string`);
      }

      const x = Number(node.position?.x ?? 0);
      const y = Number(node.position?.y ?? 0);
      if (!Number.isFinite(x) || !Number.isFinite(y)) {
        throw new HttpError(400, `nodes[${index}].position must contain numeric x and y`);
      }

      const configuredRole = node.config?.role;
      const role = configuredRole ?? (node.type === "manager" ? "manager" : "worker");
      if (role !== "manager" && role !== "worker") {
        throw new HttpError(400, `nodes[${index}].config.role must be manager or worker`);
      }

      const configuredAgent = node.config?.agentId;
      const agentId = configuredAgent ?? (role === "manager" ? "codex" : "qwen");
      if (agentId !== "codex" && agentId !== "qwen") {
        throw new HttpError(400, `nodes[${index}].config.agentId must be codex or qwen`);
      }

      const timeoutMs = assertPositiveInteger(node.config?.timeoutMs, `nodes[${index}].config.timeoutMs`);
      const maxRetries =
        assertNonNegativeInteger(node.config?.maxRetries, `nodes[${index}].config.maxRetries`) ?? 0;
      const retryDelayMs =
        assertPositiveInteger(node.config?.retryDelayMs, `nodes[${index}].config.retryDelayMs`) ?? 1_000;

      const prompt = node.config?.prompt?.trim();
      const cwd = node.config?.cwd?.trim();
      const fullAccess = assertBoolean(
        node.config?.fullAccess,
        `nodes[${index}].config.fullAccess`,
      );
      const metadata = assertObject(node.config?.metadata, `nodes[${index}].config.metadata`);

      return {
        id,
        type: node.type,
        label,
        position: {
          x,
          y,
        },
        config: {
          agentId,
          role,
          fullAccess: fullAccess ?? false,
          prompt: prompt || undefined,
          cwd: cwd || undefined,
          timeoutMs,
          maxRetries,
          retryDelayMs,
          metadata,
        },
      };
    });

    const edgeIds = new Set<string>();
    const edges = input.edges.map((edge, index): GraphEdge => {
      if (!edge || typeof edge !== "object") {
        throw new HttpError(400, `edges[${index}] must be an object`);
      }

      const id = edge.id?.trim() || randomUUID();
      if (edgeIds.has(id)) {
        throw new HttpError(400, `Duplicate edge id: ${id}`);
      }
      edgeIds.add(id);

      const fromNodeId = edge.fromNodeId?.trim();
      const toNodeId = edge.toNodeId?.trim();
      if (!fromNodeId || !toNodeId) {
        throw new HttpError(400, `edges[${index}] must contain non-empty fromNodeId and toNodeId`);
      }

      const relationType = edge.relationType ?? "dependency";
      if (
        relationType !== "dependency" &&
        relationType !== "manager_to_worker" &&
        relationType !== "peer" &&
        relationType !== "feedback"
      ) {
        throw new HttpError(
          400,
          `edges[${index}].relationType must be dependency, manager_to_worker, peer or feedback`,
        );
      }

      return {
        id,
        fromNodeId,
        toNodeId,
        relationType,
      };
    });

    const description = input.description?.trim();

    const validation = validateGraph(nodes, edges);
    if (!validation.valid) {
      throw new HttpError(
        400,
        `Graph revision ${revisionHint} is invalid: ${validation.errors.join("; ")}`,
      );
    }

    return {
      name,
      description: description || undefined,
      nodes,
      edges,
      acl: input.acl
        ? {
            editors: uniqueStrings(input.acl.editors ?? []),
            viewers: uniqueStrings(input.acl.viewers ?? []),
          }
        : undefined,
    };
  }

  private pushRunEvent(
    run: GraphRunRecord,
    type: GraphRunEvent["type"],
    data?: Record<string, unknown>,
    nodeId?: string,
  ): void {
    const event: GraphRunEvent = {
      sequence: run.nextEventSequence,
      at: new Date().toISOString(),
      type,
      runId: run.runId,
      graphId: run.graphId,
      graphRevision: run.graphRevision,
      nodeId,
      data,
    };

    run.nextEventSequence += 1;
    run.events.push(event);
    if (run.events.length > this.maxRunEvents) {
      run.events.splice(0, run.events.length - this.maxRunEvents);
    }

    this.emitter.emit(this.getRunChannel(run.runId), {
      runId: run.runId,
      status: run.status,
      cancelRequested: run.cancelRequested,
      event,
    } satisfies GraphRunStreamEvent);
  }

  private getRunRequired(runId: string): GraphRunRecord {
    const run = this.runs.get(runId);
    if (!run) {
      throw new HttpError(404, `Run ${runId} was not found`);
    }

    return run;
  }

  private getNodeAttemptRequired(attemptKey: string): NodeAttemptRecord {
    const record = this.nodeAttempts.get(attemptKey);
    if (!record) {
      throw new HttpError(404, `Node attempt ${attemptKey} was not found`);
    }

    return record;
  }

  private getNodeBucketKey(graphId: string, nodeId: string): string {
    return `${graphId}::${nodeId}`;
  }

  private getNodeBuckets<T>(source: Map<string, T[]>, nodeId: string, graphId?: string): T[][] {
    if (graphId) {
      return [source.get(this.getNodeBucketKey(graphId, nodeId)) ?? []];
    }

    const suffix = `::${nodeId}`;
    const buckets: T[][] = [];
    for (const [key, items] of source.entries()) {
      if (key !== nodeId && !key.endsWith(suffix)) {
        continue;
      }
      buckets.push(items);
    }

    return buckets;
  }

  private buildNodeSummary(output: string, max = 360): string {
    const condensed = output
      .replace(/\r?\n+/g, " ")
      .replace(/\s{2,}/g, " ")
      .trim();

    if (!condensed) {
      return "No summary available.";
    }

    if (condensed.length <= max) {
      return condensed;
    }

    return `${condensed.slice(0, max)}...[truncated ${condensed.length - max} chars]`;
  }

  private loadFromDisk(): void {
    const filePath = this.persistenceFilePath;
    if (!filePath || !existsSync(filePath)) {
      return;
    }

    let parsed: PersistedGraphStoreSnapshot;
    try {
      const raw = readFileSync(filePath, "utf8");
      const payload = JSON.parse(raw) as PersistedGraphStoreSnapshot;
      if (!payload || typeof payload !== "object") {
        return;
      }
      parsed = payload;
    } catch (error) {
      console.error("Failed to read graph store snapshot", error);
      return;
    }

    this.applySnapshot(parsed);
  }

  private applySnapshot(parsed: PersistedGraphStoreSnapshot): void {
    if (!Array.isArray(parsed.graphs) || !Array.isArray(parsed.runs)) {
      return;
    }

    this.graphs.clear();
    this.runs.clear();
    this.nodeMessages.clear();
    this.nodeLogs.clear();
    this.nodeAttempts.clear();

    for (const item of parsed.graphs) {
      const revisions = new Map<number, {
        createdAt: string;
        createdBy: string;
        nodes: GraphNode[];
        edges: GraphEdge[];
      }>();

      for (const revision of item.revisions ?? []) {
        revisions.set(revision.revision, {
          createdAt: revision.createdAt,
          createdBy: revision.createdBy,
          nodes: revision.nodes,
          edges: revision.edges,
        });
      }

      const graphRecord: GraphRecord = {
        id: item.id,
        name: item.name,
        description: item.description,
        ownerId: item.ownerId,
        acl: {
          editors: uniqueStrings(item.acl?.editors ?? []),
          viewers: uniqueStrings(item.acl?.viewers ?? []),
        },
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
        latestRevision: item.latestRevision,
        revisions,
      };

      this.graphs.set(graphRecord.id, graphRecord);
    }

    for (const rawRun of parsed.runs) {
      const run = rawRun as GraphRunRecord;
      run.nodeStates = run.nodeStates ?? {};
      run.events = Array.isArray(run.events) ? run.events : [];
      run.managerTrace = Array.isArray(run.managerTrace) ? run.managerTrace : [];
      run.nextEventSequence = this.resolveNextEventSequence(run);
      run.nextNodeLogSequence = ensureNonNegativeInteger(run.nextNodeLogSequence, 1);
      if (run.nextNodeLogSequence <= 0) {
        run.nextNodeLogSequence = 1;
      }

      this.runs.set(run.runId, run);
    }

    for (const bucket of parsed.nodeMessages ?? []) {
      if (!bucket || typeof bucket.key !== "string" || !Array.isArray(bucket.items)) {
        continue;
      }
      this.nodeMessages.set(bucket.key, bucket.items);
    }

    for (const bucket of parsed.nodeLogs ?? []) {
      if (!bucket || typeof bucket.key !== "string" || !Array.isArray(bucket.items)) {
        continue;
      }
      this.nodeLogs.set(bucket.key, bucket.items);
    }

    for (const record of parsed.nodeAttempts ?? []) {
      if (!record || typeof record.attemptKey !== "string") {
        continue;
      }
      this.nodeAttempts.set(record.attemptKey, record);
    }

    this.rebuildRunNodeLogSequences();
  }

  private buildSnapshot(): PersistedGraphStoreSnapshot {
    return {
      version: SNAPSHOT_VERSION,
      savedAt: new Date().toISOString(),
      graphs: [...this.graphs.values()].map((graph) => ({
        id: graph.id,
        name: graph.name,
        description: graph.description,
        ownerId: graph.ownerId,
        acl: clone(graph.acl),
        createdAt: graph.createdAt,
        updatedAt: graph.updatedAt,
        latestRevision: graph.latestRevision,
        revisions: [...graph.revisions.entries()]
          .sort(([left], [right]) => left - right)
          .map(([revision, value]) => ({
            revision,
            createdAt: value.createdAt,
            createdBy: value.createdBy,
            nodes: clone(value.nodes),
            edges: clone(value.edges),
          })),
      })),
      runs: [...this.runs.values()].map((run) => clone(run)),
      nodeMessages: [...this.nodeMessages.entries()].map(([key, items]) => ({
        key,
        items: clone(items),
      })),
      nodeLogs: [...this.nodeLogs.entries()].map(([key, items]) => ({
        key,
        items: clone(items),
      })),
      nodeAttempts: [...this.nodeAttempts.values()].map((record) => clone(record)),
    };
  }

  private resolveNextEventSequence(run: GraphRunRecord): number {
    const base = ensureNonNegativeInteger(run.nextEventSequence, 1);
    const maxObserved = run.events.reduce((max, event) => {
      const sequence = ensureNonNegativeInteger(event.sequence, 0);
      return Math.max(max, sequence);
    }, 0);

    return Math.max(base, maxObserved + 1, 1);
  }

  private rebuildRunNodeLogSequences(): void {
    const maxByRun = new Map<string, number>();
    for (const bucket of this.nodeLogs.values()) {
      for (const entry of bucket) {
        if (!entry.runId) {
          continue;
        }

        const current = maxByRun.get(entry.runId) ?? 0;
        maxByRun.set(entry.runId, Math.max(current, entry.sequence));
      }
    }

    for (const run of this.runs.values()) {
      const maxSequence = maxByRun.get(run.runId) ?? 0;
      run.nextNodeLogSequence = Math.max(run.nextNodeLogSequence, maxSequence + 1, 1);
    }
  }

  private toGraphSnapshot(record: GraphRecord, revisionNumber: number): OrchestrationGraph {
    const revision = record.revisions.get(revisionNumber);
    if (!revision) {
      throw new HttpError(404, `Revision ${revisionNumber} for graph ${record.id} was not found`);
    }

    const snapshot: OrchestrationGraph = {
      id: record.id,
      name: record.name,
      description: record.description,
      ownerId: record.ownerId,
      acl: clone(record.acl),
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      latestRevision: record.latestRevision,
      revisionHistory: [...record.revisions.keys()].sort((a, b) => a - b),
      revision: {
        revision: revisionNumber,
        createdAt: revision.createdAt,
        createdBy: revision.createdBy,
        nodes: clone(revision.nodes),
        edges: clone(revision.edges),
      },
    };

    return snapshot;
  }

  private toRunSnapshot(run: GraphRunRecord): GraphRun {
    const { nextEventSequence, nextNodeLogSequence, ...snapshot } = run;
    void nextEventSequence;
    void nextNodeLogSequence;
    return clone(snapshot);
  }

  private canRead(actor: AuthActor, graph: GraphRecord): boolean {
    if (actor.role === "admin") {
      return true;
    }

    if (graph.ownerId === actor.userId) {
      return true;
    }

    if (graph.acl.editors.includes(actor.userId)) {
      return true;
    }

    if (graph.acl.viewers.includes(actor.userId)) {
      return true;
    }

    return false;
  }

  private canWrite(actor: AuthActor, graph: GraphRecord): boolean {
    if (actor.role === "admin") {
      return true;
    }

    if (graph.ownerId === actor.userId) {
      return true;
    }

    return graph.acl.editors.includes(actor.userId);
  }

  private assertReadable(actor: AuthActor, graph: GraphRecord): void {
    if (this.canRead(actor, graph)) {
      return;
    }

    throw new HttpError(403, `Access denied for graph ${graph.id}`);
  }

  private assertWritable(actor: AuthActor, graph: GraphRecord): void {
    if (this.canWrite(actor, graph)) {
      return;
    }

    throw new HttpError(403, `Write access denied for graph ${graph.id}`);
  }

  private getRunChannel(runId: string): string {
    return `graph-run:${runId}`;
  }

  private persistState(): void {
    const snapshot = this.buildSnapshot();

    const filePath = this.persistenceFilePath;
    if (filePath) {
      try {
        mkdirSync(path.dirname(filePath), { recursive: true });
        writeFileSync(filePath, JSON.stringify(snapshot), "utf8");
      } catch (error) {
        console.error("Failed to persist graph store snapshot", error);
        throw error;
      }
    }

    if (this.onPersistSnapshot) {
      try {
        this.onPersistSnapshot(snapshot);
      } catch (error) {
        console.error("Graph store snapshot callback failed", error);
      }
    }
  }
}
