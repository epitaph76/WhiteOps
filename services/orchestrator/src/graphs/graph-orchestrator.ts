import { AgentRunner, RunResult } from "../types";
import { GraphStore } from "./graph-store";
import { GraphEdge, GraphNode, GraphRun, NodeArtifacts } from "./graph-types";

interface GraphOrchestratorOptions {
  defaultNodeTimeoutMs: number;
  maxNodeTimeoutMs: number;
  defaultCwd?: string;
  maxParallelNodes: number;
}

interface ParsedManagerAssignment {
  workerNodeId?: string;
  workerLabel?: string;
  task?: string;
  reason?: string;
}

const MAX_DEPENDENCY_OUTPUT = 4_000;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function truncateText(source: string, max: number): string {
  if (source.length <= max) {
    return source;
  }

  return `${source.slice(0, max)}\n...[truncated ${source.length - max} chars]`;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }

  return value as Record<string, unknown>;
}

function pickString(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value !== "string") {
      continue;
    }

    const trimmed = value.trim();
    if (trimmed) {
      return trimmed;
    }
  }

  return undefined;
}

function extractFirstJsonObject(source: string): string | undefined {
  let depth = 0;
  let inString = false;
  let escaped = false;
  let start = -1;

  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];

    if (inString) {
      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === "\\") {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = false;
      }

      continue;
    }

    if (char === '"') {
      inString = true;
      continue;
    }

    if (char === "{") {
      if (depth === 0) {
        start = index;
      }
      depth += 1;
      continue;
    }

    if (char === "}") {
      if (depth === 0) {
        continue;
      }

      depth -= 1;
      if (depth === 0 && start >= 0) {
        return source.slice(start, index + 1);
      }
    }
  }

  return undefined;
}

function parseJsonObject(source: string): Record<string, unknown> | undefined {
  const trimmed = source.trim();
  if (!trimmed) {
    return undefined;
  }

  const candidates: string[] = [trimmed];
  const firstJson = extractFirstJsonObject(trimmed);
  if (firstJson) {
    candidates.push(firstJson);
  }

  const fenced = [...trimmed.matchAll(/```(?:json)?\s*([\s\S]*?)```/gi)];
  for (const match of fenced) {
    const payload = match[1]?.trim();
    if (payload) {
      candidates.push(payload);
    }
  }

  const seen = new Set<string>();
  for (const candidate of candidates) {
    if (seen.has(candidate)) {
      continue;
    }
    seen.add(candidate);

    try {
      const parsed = JSON.parse(candidate);
      const record = asRecord(parsed);
      if (record) {
        return record;
      }
    } catch {
      // Continue trying candidate payloads.
    }
  }

  return undefined;
}

function parseResultFiles(value: unknown): string[] {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed ? [trimmed] : [];
  }

  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item) => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function extractArtifactsFromOutput(output: string): NodeArtifacts {
  const parsed = parseJsonObject(output);

  const stdout = parsed ? pickString(parsed.stdout, parsed.output) : undefined;
  const stderr = parsed ? pickString(parsed.stderr, parsed.error) : undefined;
  const diffPatch = parsed ? pickString(parsed.diffPatch, parsed.diff, parsed.patch) : undefined;
  const resultFiles = parsed
    ? parseResultFiles(parsed.resultFiles ?? parsed.files ?? parsed.fileLinks)
    : [];

  return {
    stdout: stdout ?? output,
    stderr,
    diffPatch,
    resultFiles,
    rawOutput: output,
  };
}

function parseManagerAssignments(output: string): ParsedManagerAssignment[] {
  const parsed = parseJsonObject(output);
  if (!parsed) {
    return [];
  }

  const assignments: ParsedManagerAssignment[] = [];

  const assignmentList = parsed.assignments;
  if (Array.isArray(assignmentList)) {
    for (const item of assignmentList) {
      const entry = asRecord(item);
      if (!entry) {
        continue;
      }

      assignments.push({
        workerNodeId: pickString(entry.workerNodeId, entry.nodeId, entry.workerId),
        workerLabel: pickString(entry.workerLabel, entry.label, entry.worker),
        task: pickString(entry.task, entry.instructions, entry.prompt, entry.title),
        reason: pickString(entry.reason, entry.rationale, entry.why),
      });
    }
  }

  const workersList = parsed.workers;
  if (Array.isArray(workersList)) {
    for (const item of workersList) {
      const entry = asRecord(item);
      if (!entry) {
        continue;
      }

      assignments.push({
        workerNodeId: pickString(entry.workerNodeId, entry.nodeId, entry.id),
        workerLabel: pickString(entry.workerLabel, entry.label, entry.name),
        task: pickString(entry.task, entry.instructions, entry.prompt, entry.title),
        reason: pickString(entry.reason, entry.rationale, entry.why),
      });
    }
  }

  return assignments;
}

function buildDependencyMap(nodes: GraphNode[], edges: GraphEdge[]): Map<string, string[]> {
  const map = new Map<string, string[]>();
  for (const node of nodes) {
    map.set(node.id, []);
  }

  for (const edge of edges) {
    map.set(edge.toNodeId, [...(map.get(edge.toNodeId) ?? []), edge.fromNodeId]);
  }

  return map;
}

function isTerminal(status: GraphRun["nodeStates"][string]["status"]): boolean {
  return (
    status === "completed" ||
    status === "failed" ||
    status === "canceled" ||
    status === "skipped"
  );
}

function isManagerNode(node: GraphNode): boolean {
  return node.type === "manager" || node.config.role === "manager";
}

export class GraphOrchestrator {
  private readonly runningRuns = new Set<string>();

  constructor(
    private readonly runner: AgentRunner,
    private readonly store: GraphStore,
    private readonly options: GraphOrchestratorOptions,
  ) {}

  startRunInBackground(runId: string): void {
    if (this.runningRuns.has(runId)) {
      return;
    }

    setImmediate(() => {
      void this.executeRun(runId);
    });
  }

  getRunningRunsCount(): number {
    return this.runningRuns.size;
  }

  private async executeRun(runId: string): Promise<void> {
    if (this.runningRuns.has(runId)) {
      return;
    }

    const initial = this.store.getRunForExecution(runId);
    if (!initial) {
      return;
    }

    this.runningRuns.add(runId);

    try {
      this.store.markRunStarted(runId);
      const snapshot = this.store.getRunForExecution(runId);
      if (!snapshot) {
        return;
      }

      const dependencies = buildDependencyMap(snapshot.nodes, snapshot.edges);
      for (const node of snapshot.nodes) {
        if ((dependencies.get(node.id) ?? []).length === 0) {
          this.store.setNodeStatus(runId, node.id, "ready");
        }
      }

      const nodeById = new Map(snapshot.nodes.map((node) => [node.id, node]));
      const pending = new Set(snapshot.nodes.map((node) => node.id));
      const active = new Map<string, Promise<void>>();

      while (pending.size > 0 || active.size > 0) {
        if (this.store.isRunCancelRequested(runId)) {
          const runState = this.store.getRunForExecution(runId);
          if (runState) {
            for (const nodeId of pending) {
              const state = runState.nodeStates[nodeId];
              if (!state || isTerminal(state.status)) {
                continue;
              }

              this.store.setNodeStatus(runId, nodeId, "canceled", {
                attempts: state.attempts,
                lastError: "Run canceled",
              });
            }
          }

          pending.clear();
          if (active.size > 0) {
            await Promise.allSettled([...active.values()]);
          }
          break;
        }

        const current = this.store.getRunForExecution(runId);
        if (!current) {
          break;
        }

        for (const nodeId of [...pending]) {
          const state = current.nodeStates[nodeId];
          if (!state) {
            pending.delete(nodeId);
            continue;
          }

          if (isTerminal(state.status)) {
            pending.delete(nodeId);
            continue;
          }

          const upstream = dependencies.get(nodeId) ?? [];
          const upstreamStatuses = upstream
            .map((dependencyNodeId) => current.nodeStates[dependencyNodeId]?.status)
            .filter((status): status is NonNullable<typeof status> => Boolean(status));

          const blocked = upstreamStatuses.some(
            (status) => status === "failed" || status === "canceled" || status === "skipped",
          );

          if (blocked) {
            this.store.setNodeStatus(runId, nodeId, "skipped", {
              attempts: state.attempts,
              lastError: "Skipped because an upstream node did not complete successfully",
            });
            pending.delete(nodeId);
          }
        }

        const refreshed = this.store.getRunForExecution(runId);
        if (!refreshed) {
          break;
        }

        const readyCandidates = [...pending].filter((nodeId) => {
          if (active.has(nodeId)) {
            return false;
          }

          const state = refreshed.nodeStates[nodeId];
          if (!state) {
            return false;
          }

          if (state.status !== "pending" && state.status !== "ready") {
            return false;
          }

          const upstream = dependencies.get(nodeId) ?? [];
          if (upstream.length === 0) {
            return true;
          }

          return upstream.every(
            (dependencyNodeId) => refreshed.nodeStates[dependencyNodeId]?.status === "completed",
          );
        });

        while (
          readyCandidates.length > 0 &&
          active.size < Math.max(1, this.options.maxParallelNodes)
        ) {
          const nodeId = readyCandidates.shift();
          if (!nodeId) {
            break;
          }

          const node = nodeById.get(nodeId);
          if (!node) {
            pending.delete(nodeId);
            continue;
          }

          const state = refreshed.nodeStates[nodeId];
          if (state && state.status === "pending") {
            this.store.setNodeStatus(runId, nodeId, "ready", {
              attempts: state.attempts,
            });
          }

          const job = this.executeNode(runId, node, dependencies.get(node.id) ?? []).finally(() => {
            active.delete(node.id);
          });
          active.set(node.id, job);
        }

        if (active.size === 0) {
          if (pending.size === 0) {
            break;
          }

          const unresolved = this.store.getRunForExecution(runId);
          if (!unresolved) {
            break;
          }

          for (const nodeId of pending) {
            const state = unresolved.nodeStates[nodeId];
            if (!state || isTerminal(state.status)) {
              continue;
            }

            this.store.setNodeStatus(runId, nodeId, "failed", {
              attempts: state.attempts,
              lastError: "Node could not be scheduled due unresolved dependencies",
            });
          }
          pending.clear();
          break;
        }

        await Promise.race([...active.values()]);

        const postRace = this.store.getRunForExecution(runId);
        if (!postRace) {
          break;
        }

        for (const nodeId of [...pending]) {
          const state = postRace.nodeStates[nodeId];
          if (state && isTerminal(state.status)) {
            pending.delete(nodeId);
          }
        }
      }

      const finalSnapshot = this.store.getRunForExecution(runId);
      if (!finalSnapshot) {
        return;
      }

      const nodeStates = Object.values(finalSnapshot.nodeStates);
      const hasFailure = nodeStates.some((state) => state.status === "failed");
      const hasCancellation = nodeStates.some((state) => state.status === "canceled");

      if (finalSnapshot.cancelRequested || hasCancellation) {
        this.store.markRunFinished(runId, "canceled", "Run canceled");
      } else if (hasFailure) {
        this.store.markRunFinished(runId, "failed", "One or more nodes failed");
      } else {
        this.store.markRunFinished(runId, "completed");
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : "Graph run failed";
      this.store.markRunFinished(runId, "failed", message);
    } finally {
      this.runningRuns.delete(runId);
    }
  }

  private async executeNode(runId: string, node: GraphNode, dependencyIds: string[]): Promise<void> {
    const timeoutMsRaw = node.config.timeoutMs ?? this.options.defaultNodeTimeoutMs;
    const timeoutMs = Math.max(1, Math.min(timeoutMsRaw, this.options.maxNodeTimeoutMs));
    const maxRetries = Math.max(0, node.config.maxRetries ?? 0);
    const retryDelayMs = Math.max(1, node.config.retryDelayMs ?? 1_000);

    for (let attempt = 1; attempt <= maxRetries + 1; attempt += 1) {
      if (this.store.isRunCancelRequested(runId)) {
        this.store.setNodeStatus(runId, node.id, "canceled", {
          attempts: attempt - 1,
          lastError: "Run canceled before node start",
        });
        return;
      }

      const status = attempt === 1 ? "running" : "retrying";
      this.store.setNodeStatus(runId, node.id, status, {
        attempts: attempt,
      });

      this.store.appendNodeLog(
        runId,
        node.id,
        "system",
        `Attempt ${attempt}/${maxRetries + 1} started`,
      );

      const prompt = this.buildPrompt(runId, node, dependencyIds);

      try {
        const result = await this.runner.run(node.config.agentId, prompt, {
          cwd: node.config.cwd ?? this.options.defaultCwd,
          timeoutMs,
        });

        if (this.store.isRunCancelRequested(runId)) {
          this.store.setNodeStatus(runId, node.id, "canceled", {
            attempts: attempt,
            lastError: "Run canceled during node execution",
          });
          return;
        }

        this.store.appendNodeLog(runId, node.id, "stdout", truncateText(result.output, 30_000));

        if (result.timedOut) {
          const timeoutError = `Node timed out after ${timeoutMs}ms`;
          this.store.appendNodeLog(runId, node.id, "stderr", timeoutError);

          if (attempt <= maxRetries) {
            this.store.setNodeStatus(runId, node.id, "retrying", {
              attempts: attempt,
              lastError: timeoutError,
            });
            await sleep(retryDelayMs);
            continue;
          }

          this.store.setNodeStatus(runId, node.id, "failed", {
            attempts: attempt,
            lastError: timeoutError,
          });
          return;
        }

        const artifacts = extractArtifactsFromOutput(result.output);
        this.store.setNodeResult(runId, node.id, result, artifacts);

        if (isManagerNode(node)) {
          this.createManagerTraceEntries(runId, node, result);
        }

        return;
      } catch (error) {
        const message = error instanceof Error ? error.message : "Node execution failed";
        this.store.appendNodeLog(runId, node.id, "stderr", message);

        if (attempt <= maxRetries && !this.store.isRunCancelRequested(runId)) {
          this.store.setNodeStatus(runId, node.id, "retrying", {
            attempts: attempt,
            lastError: message,
          });
          await sleep(retryDelayMs);
          continue;
        }

        this.store.setNodeStatus(
          runId,
          node.id,
          this.store.isRunCancelRequested(runId) ? "canceled" : "failed",
          {
            attempts: attempt,
            lastError: message,
          },
        );
        return;
      }
    }
  }

  private buildPrompt(runId: string, node: GraphNode, dependencyIds: string[]): string {
    const run = this.store.getRunForExecution(runId);
    if (!run) {
      return node.config.prompt?.trim() || `Execute node '${node.label}'.`;
    }

    const dependenciesSection = dependencyIds
      .map((dependencyId) => {
        const state = run.nodeStates[dependencyId];
        const dependencyNode = run.nodes.find((candidate) => candidate.id === dependencyId);
        const header = dependencyNode
          ? `${dependencyNode.label} (${dependencyNode.id})`
          : dependencyId;

        if (!state?.result) {
          return `Dependency ${header}: no output`;
        }

        return [
          `Dependency ${header}:`,
          truncateText(state.result.output, MAX_DEPENDENCY_OUTPUT),
        ].join("\n");
      })
      .join("\n\n");

    const basePrompt =
      node.config.prompt?.trim() ||
      [
        `You are node '${node.label}' (${node.id}) in orchestration run ${runId}.`,
        "Execute your part of the task and return a concise result.",
      ].join(" ");

    const assignmentSection = this.buildManagerAssignmentSection(run, node.id);
    const kickoffSection = this.buildRunKickoffSection(run, node);

    const sections = [basePrompt];
    if (kickoffSection) {
      sections.push("Run kickoff task:", kickoffSection);
    }
    if (assignmentSection) {
      sections.push("Manager assignments:", assignmentSection);
    }
    if (dependenciesSection) {
      sections.push("Upstream context:", dependenciesSection);
    }

    return sections.join("\n\n");
  }

  private buildRunKickoffSection(run: GraphRun, node: GraphNode): string | undefined {
    const kickoff = run.kickoffMessage?.trim();
    if (!kickoff) {
      return undefined;
    }

    if (!isManagerNode(node)) {
      return undefined;
    }

    if (run.kickoffManagerNodeId && run.kickoffManagerNodeId !== node.id) {
      return undefined;
    }

    return kickoff;
  }

  private buildManagerAssignmentSection(run: GraphRun, workerNodeId: string): string | undefined {
    const assignments = run.managerTrace
      .filter((entry) => entry.workerNodeId === workerNodeId)
      .sort((left, right) => left.assignedAt.localeCompare(right.assignedAt))
      .slice(-3);

    if (assignments.length === 0) {
      return undefined;
    }

    return assignments
      .map((entry) => {
        const note = entry.note?.trim();
        const parts = [
          `- task: ${entry.task}`,
          `  reason: ${entry.reason}`,
          `  status: ${entry.confirmationStatus}`,
        ];
        if (note) {
          parts.push(`  note: ${note}`);
        }
        return parts.join("\n");
      })
      .join("\n");
  }

  private createManagerTraceEntries(runId: string, managerNode: GraphNode, result: RunResult): void {
    const run = this.store.getRunForExecution(runId);
    if (!run) {
      return;
    }

    const outgoing = run.edges.filter((edge) => edge.fromNodeId === managerNode.id);
    if (outgoing.length === 0) {
      return;
    }

    const parsedAssignments = parseManagerAssignments(result.output);
    const managerOutputTask =
      result.output.trim() && parsedAssignments.length === 0
        ? truncateText(result.output.trim(), MAX_DEPENDENCY_OUTPUT)
        : undefined;

    for (const edge of outgoing) {
      const worker = run.nodes.find((node) => node.id === edge.toNodeId);
      if (!worker) {
        continue;
      }

      const assignment = parsedAssignments.find((candidate) => {
        if (candidate.workerNodeId && candidate.workerNodeId === worker.id) {
          return true;
        }

        if (candidate.workerLabel && candidate.workerLabel.toLowerCase() === worker.label.toLowerCase()) {
          return true;
        }

        return false;
      });

      this.store.addManagerTraceEntry(runId, {
        managerNodeId: managerNode.id,
        workerNodeId: worker.id,
        task:
          assignment?.task ||
          managerOutputTask ||
          `Execute task assigned by manager '${managerNode.label}' for worker '${worker.label}'`,
        reason: assignment?.reason || `relationType=${edge.relationType}`,
      });
    }
  }
}
