import { AgentId, RunResult } from "../types";

export type GraphNodeType = "manager" | "worker" | "agent";
export type GraphRelationType = "manager_to_worker" | "dependency" | "peer" | "feedback";

export interface GraphNodePosition {
  x: number;
  y: number;
}

export interface GraphNodeConfig {
  agentId: AgentId;
  role: "manager" | "worker";
  fullAccess?: boolean;
  prompt?: string;
  cwd?: string;
  timeoutMs?: number;
  maxRetries?: number;
  retryDelayMs?: number;
  metadata?: Record<string, unknown>;
}

export interface GraphNode {
  id: string;
  type: GraphNodeType;
  label: string;
  position: GraphNodePosition;
  config: GraphNodeConfig;
}

export interface GraphEdge {
  id: string;
  fromNodeId: string;
  toNodeId: string;
  relationType: GraphRelationType;
}

export interface GraphAcl {
  editors: string[];
  viewers: string[];
}

export interface GraphRevision {
  revision: number;
  createdAt: string;
  createdBy: string;
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export interface OrchestrationGraph {
  id: string;
  name: string;
  description?: string;
  ownerId: string;
  acl: GraphAcl;
  createdAt: string;
  updatedAt: string;
  latestRevision: number;
  revisionHistory: number[];
  revision: GraphRevision;
}

export interface GraphNodeInput {
  id?: string;
  type: GraphNodeType;
  label: string;
  position?: Partial<GraphNodePosition>;
  config?: Partial<GraphNodeConfig>;
}

export interface GraphEdgeInput {
  id?: string;
  fromNodeId: string;
  toNodeId: string;
  relationType?: GraphRelationType;
}

export interface GraphUpsertInput {
  name: string;
  description?: string;
  nodes: GraphNodeInput[];
  edges: GraphEdgeInput[];
  acl?: Partial<GraphAcl>;
}

export interface GraphValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
  topologicalOrder: string[];
}

export type GraphRunStatus = "queued" | "running" | "completed" | "failed" | "canceled";

export type NodeExecutionStatus =
  | "pending"
  | "ready"
  | "running"
  | "retrying"
  | "completed"
  | "failed"
  | "canceled"
  | "skipped";

export type GraphRealtimeEventType =
  | "graph_run_started"
  | "node_status_changed"
  | "node_log_chunk"
  | "node_result_ready"
  | "graph_run_finished";

export interface GraphRunEvent {
  sequence: number;
  at: string;
  type: GraphRealtimeEventType;
  runId: string;
  graphId: string;
  graphRevision: number;
  nodeId?: string;
  data?: Record<string, unknown>;
}

export interface NodeArtifacts {
  diffPatch?: string;
  stdout?: string;
  stderr?: string;
  resultFiles: string[];
  rawOutput?: string;
}

export interface GraphRunNodeState {
  nodeId: string;
  status: NodeExecutionStatus;
  attempts: number;
  lastPrompt?: string;
  startedAt?: string;
  finishedAt?: string;
  lastError?: string;
  result?: RunResult;
  artifacts?: NodeArtifacts;
}

export interface ManagerTraceEntry {
  id: string;
  runId: string;
  managerNodeId: string;
  workerNodeId: string;
  task: string;
  reason: string;
  confirmationStatus: "pending" | "confirmed" | "failed";
  assignedAt: string;
  confirmedAt?: string;
  note?: string;
}

export interface GraphRun {
  runId: string;
  graphId: string;
  graphRevision: number;
  kickoffMessage?: string;
  kickoffManagerNodeId?: string;
  requestedBy: string;
  status: GraphRunStatus;
  cancelRequested: boolean;
  createdAt: string;
  updatedAt: string;
  startedAt?: string;
  finishedAt?: string;
  error?: string;
  nodes: GraphNode[];
  edges: GraphEdge[];
  nodeStates: Record<string, GraphRunNodeState>;
  managerTrace: ManagerTraceEntry[];
  events: GraphRunEvent[];
}

export interface GraphRunStreamEvent {
  runId: string;
  status: GraphRunStatus;
  cancelRequested: boolean;
  event: GraphRunEvent;
}

export type NodeMessageRole = "user" | "assistant" | "system";

export interface NodeChatMessage {
  id: string;
  graphId: string;
  nodeId: string;
  runId?: string;
  role: NodeMessageRole;
  text: string;
  createdAt: string;
}

export type NodeLogStream = "stdout" | "stderr" | "system";

export interface NodeLogEntry {
  id: string;
  graphId: string;
  nodeId: string;
  runId?: string;
  stream: NodeLogStream;
  chunk: string;
  sequence: number;
  createdAt: string;
}

export interface ResolvedGraphNode {
  graphId: string;
  graphRevision: number;
  node: GraphNode;
}
