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

function buildAttemptKey(runId: string, nodeId: string, attempt: number): string {
  return `${runId}:${nodeId}:attempt:${attempt}`;
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

function summarizeMetadata(metadata: Record<string, unknown> | undefined): string | undefined {
  if (!metadata) {
    return undefined;
  }

  const entries: string[] = [];
  for (const [key, value] of Object.entries(metadata)) {
    if (value == null) {
      continue;
    }
    if (typeof value === "string") {
      const normalized = value.trim();
      if (normalized) {
        entries.push(`${key}: ${normalized}`);
      }
      continue;
    }
    if (typeof value === "number" || typeof value === "boolean") {
      entries.push(`${key}: ${String(value)}`);
      continue;
    }
    try {
      entries.push(`${key}: ${JSON.stringify(value)}`);
    } catch {
      // Ignore non-serializable metadata fragments.
    }
  }

  if (entries.length === 0) {
    return undefined;
  }

  return truncateText(entries.join("; "), 1_200);
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

function extractShortSummary(output: string, max = 360): string {
  const parsed = parseJsonObject(output);
  const structuredSummary = parsed
    ? pickString(
        parsed.summary,
        parsed.finalSummary,
        parsed.resultSummary,
        parsed.result,
        parsed.message,
        parsed.output,
      )
    : undefined;

  const fallbackSource = structuredSummary ?? output;
  const condensed = fallbackSource
    .replace(/\r?\n+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();

  if (!condensed) {
    return "No summary available.";
  }

  return truncateText(condensed, max);
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
    if (edge.relationType === "feedback") {
      continue;
    }
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

  resumeRecoverableRuns(limit = 100): string[] {
    const runIds = this.store.listRecoverableRunIds(limit);
    for (const runId of runIds) {
      this.startRunInBackground(runId);
    }
    return runIds;
  }

  private async executeRun(runId: string): Promise<void> {
    if (this.runningRuns.has(runId)) {
      return;
    }

    const initial = this.store.recoverRunForExecution(runId);
    if (!initial) {
      return;
    }
    if (initial.status !== "queued" && initial.status !== "running") {
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

      const finalStatus =
        finalSnapshot.cancelRequested || hasCancellation
          ? "canceled"
          : hasFailure
          ? "failed"
          : "completed";
      const finalError =
        finalStatus === "canceled"
          ? "Run canceled"
          : finalStatus === "failed"
          ? "One or more nodes failed"
          : undefined;

      this.store.markRunFinished(runId, finalStatus, finalError);
      this.publishRunSummaryToManagers(
        this.store.getRunForExecution(runId) ?? finalSnapshot,
        finalStatus,
      );
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
    const runSnapshot = this.store.getRunForExecution(runId);
    const runDefaultCwd = runSnapshot?.cwd?.trim() || undefined;

    for (let attempt = 1; attempt <= maxRetries + 1; attempt += 1) {
      const attemptKey = buildAttemptKey(runId, node.id, attempt);
      if (this.store.isRunCancelRequested(runId)) {
        this.store.setNodeStatus(runId, node.id, "canceled", {
          attempts: attempt - 1,
          lastAttemptKey: attemptKey,
          lastError: "Run canceled before node start",
        });
        return;
      }

      const prompt = this.buildPrompt(runId, node, dependencyIds);
      const attemptClaim = this.store.claimNodeAttempt(runId, node.id, attempt, attemptKey);
      if (!attemptClaim.isNewClaim) {
        const reused = attemptClaim.record;
        if (reused.status === "claimed") {
          this.store.appendNodeLog(
            runId,
            node.id,
            "system",
            `Attempt ${attemptKey} is already in-flight; skipping duplicate scheduler invocation`,
          );
          return;
        }

        if (reused.status === "completed" && reused.result && reused.artifacts) {
          this.store.appendNodeLog(
            runId,
            node.id,
            "system",
            `Idempotency hit for ${attemptKey}: reusing cached result`,
          );
          this.store.setNodeResult(runId, node.id, reused.result, reused.artifacts);

          if (isManagerNode(node)) {
            const currentRun = this.store.getRunForExecution(runId);
            const hasManagerTrace = Boolean(
              currentRun?.managerTrace.some((item) => item.managerNodeId === node.id),
            );
            if (!hasManagerTrace) {
              this.createManagerTraceEntries(runId, node, reused.result);
            }
          } else {
            this.notifyManagersAboutSubordinateCompletion(runId, node.id, "completed");
          }

          return;
        }

        if (reused.status === "failed") {
          const message = reused.error || "Cached attempt failed";
          this.store.appendNodeLog(
            runId,
            node.id,
            "system",
            `Idempotency hit for ${attemptKey}: cached failure '${message}'`,
          );

          if (attempt <= maxRetries && !this.store.isRunCancelRequested(runId)) {
            this.store.setNodeStatus(runId, node.id, "retrying", {
              attempts: attempt,
              lastAttemptKey: attemptKey,
              lastPrompt: prompt,
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
              lastAttemptKey: attemptKey,
              lastPrompt: prompt,
              lastError: message,
            },
          );
          if (!isManagerNode(node)) {
            this.notifyManagersAboutSubordinateCompletion(
              runId,
              node.id,
              this.store.isRunCancelRequested(runId) ? "canceled" : "failed",
            );
          }
          return;
        }

        if (reused.status === "canceled") {
          const message = reused.error || "Cached attempt canceled";
          this.store.appendNodeLog(
            runId,
            node.id,
            "system",
            `Idempotency hit for ${attemptKey}: cached cancellation`,
          );
          this.store.setNodeStatus(runId, node.id, "canceled", {
            attempts: attempt,
            lastAttemptKey: attemptKey,
            lastPrompt: prompt,
            lastError: message,
          });
          if (!isManagerNode(node)) {
            this.notifyManagersAboutSubordinateCompletion(runId, node.id, "canceled");
          }
          return;
        }
      }

      const status = attempt === 1 ? "running" : "retrying";
      this.store.setNodeStatus(runId, node.id, status, {
        attempts: attempt,
        lastAttemptKey: attemptKey,
        lastPrompt: prompt,
      });

      this.store.appendNodeLog(
        runId,
        node.id,
        "system",
        `Attempt ${attempt}/${maxRetries + 1} started`,
      );

      try {
        const result = await this.runner.run(node.config.agentId, prompt, {
          cwd: node.config.cwd ?? runDefaultCwd ?? this.options.defaultCwd,
          timeoutMs,
          fullAccess: node.config.fullAccess === true,
        });

        if (this.store.isRunCancelRequested(runId)) {
          this.store.cancelNodeAttempt(attemptKey, "Run canceled during node execution");
          this.store.setNodeStatus(runId, node.id, "canceled", {
            attempts: attempt,
            lastAttemptKey: attemptKey,
            lastError: "Run canceled during node execution",
          });
          return;
        }

        this.store.appendNodeLog(runId, node.id, "stdout", truncateText(result.output, 30_000));

        if (result.timedOut) {
          const timeoutError = `Node timed out after ${timeoutMs}ms`;
          this.store.appendNodeLog(runId, node.id, "stderr", timeoutError);
          this.store.failNodeAttempt(attemptKey, timeoutError);

          if (attempt <= maxRetries) {
            this.store.setNodeStatus(runId, node.id, "retrying", {
              attempts: attempt,
              lastAttemptKey: attemptKey,
              lastPrompt: prompt,
              lastError: timeoutError,
            });
            await sleep(retryDelayMs);
            continue;
          }

          this.store.setNodeStatus(runId, node.id, "failed", {
            attempts: attempt,
            lastAttemptKey: attemptKey,
            lastPrompt: prompt,
            lastError: timeoutError,
          });
          if (!isManagerNode(node)) {
            this.notifyManagersAboutSubordinateCompletion(runId, node.id, "failed");
          }
          return;
        }

        const artifacts = extractArtifactsFromOutput(result.output);
        this.store.completeNodeAttempt(attemptKey, result, artifacts);
        this.store.setNodeResult(runId, node.id, result, artifacts);

        if (isManagerNode(node)) {
          this.createManagerTraceEntries(runId, node, result);
        } else {
          this.notifyManagersAboutSubordinateCompletion(runId, node.id, "completed");
        }

        return;
      } catch (error) {
        const message = error instanceof Error ? error.message : "Node execution failed";
        this.store.appendNodeLog(runId, node.id, "stderr", message);
        if (this.store.isRunCancelRequested(runId)) {
          this.store.cancelNodeAttempt(attemptKey, message);
        } else {
          this.store.failNodeAttempt(attemptKey, message);
        }

        if (attempt <= maxRetries && !this.store.isRunCancelRequested(runId)) {
          this.store.setNodeStatus(runId, node.id, "retrying", {
            attempts: attempt,
            lastAttemptKey: attemptKey,
            lastPrompt: prompt,
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
            lastAttemptKey: attemptKey,
            lastPrompt: prompt,
            lastError: message,
          },
        );
        if (!isManagerNode(node)) {
          this.notifyManagersAboutSubordinateCompletion(
            runId,
            node.id,
            this.store.isRunCancelRequested(runId) ? "canceled" : "failed",
          );
        }
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

        const summary = state.summary?.trim() || extractShortSummary(state.result.output);
        const resultFiles = state.artifacts?.resultFiles ?? [];
        const linksLine =
          resultFiles.length > 0
            ? `resultFiles: ${resultFiles.slice(0, 6).join(", ")}`
            : "resultFiles: none";

        return [`Dependency ${header}:`, `summary: ${summary}`, linksLine].join("\n");
      })
      .join("\n\n");

    const basePrompt =
      node.config.prompt?.trim() ||
      (isManagerNode(node)
        ? [
            `You are node '${node.label}' (${node.id}) in orchestration run ${runId}.`,
            "You are the manager agent responsible for planning and delegating tasks to connected subordinate nodes.",
            "Return concise, execution-ready assignments for subordinates.",
          ].join(" ")
        : [
            `You are node '${node.label}' (${node.id}) in orchestration run ${runId}.`,
            "Execute your part of the task and return a concise result.",
          ].join(" "));

    const assignmentSection = this.buildManagerAssignmentSection(run, node.id);
    const kickoffSection = this.buildRunKickoffSection(run, node);
    const managerPlanningSection = this.buildManagerPlanningSection(run, node);
    const subordinatesSection = this.buildManagerSubordinatesSection(run, node);

    const sections = [basePrompt];
    if (subordinatesSection) {
      sections.push("Connected subordinate profiles:", subordinatesSection);
    }
    if (managerPlanningSection) {
      sections.push("Manager planning requirements:", managerPlanningSection);
    }
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

  private buildManagerSubordinatesSection(run: GraphRun, node: GraphNode): string | undefined {
    if (!isManagerNode(node)) {
      return undefined;
    }

    const lines: string[] = [];
    for (const edge of run.edges) {
      if (edge.fromNodeId !== node.id) {
        continue;
      }

      const worker = run.nodes.find((candidate) => candidate.id === edge.toNodeId);
      if (!worker) {
        continue;
      }

      const metadataSummary = summarizeMetadata(worker.config.metadata);
      const profile = [
        `- ${worker.label} (${worker.id})`,
        `  type=${worker.type}`,
        `  role=${worker.config.role}`,
        `  agent=${worker.config.agentId}`,
        `  relationType=${edge.relationType}`,
      ];
      if (metadataSummary) {
        profile.push(`  metadata=${metadataSummary}`);
      }
      lines.push(profile.join("\n"));
    }

    if (lines.length === 0) {
      return undefined;
    }

    return lines.join("\n");
  }

  private buildManagerPlanningSection(run: GraphRun, node: GraphNode): string | undefined {
    if (!isManagerNode(node)) {
      return undefined;
    }

    const workers: Array<{ id: string; label: string; relationType: string }> = [];
    for (const edge of run.edges) {
      if (edge.fromNodeId !== node.id) {
        continue;
      }

      const worker = run.nodes.find((candidate) => candidate.id === edge.toNodeId);
      if (!worker) {
        continue;
      }

      workers.push({
        id: worker.id,
        label: worker.label,
        relationType: edge.relationType,
      });
    }

    if (workers.length === 0) {
      return undefined;
    }

    return [
      "Return strict JSON object only (no markdown) with field 'assignments' as an array.",
      "Create exactly one assignment item per worker listed below.",
      "Each item must include: workerNodeId, task, reason.",
      "Tasks must be mutually exclusive and non-overlapping.",
      "Workers:",
      ...workers.map(
        (worker) =>
          `- ${worker.label} (${worker.id}), relationType=${worker.relationType}`,
      ),
    ].join("\n");
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
    const managerOutputTask = result.output.trim()
      ? truncateText(result.output.trim(), MAX_DEPENDENCY_OUTPUT)
      : undefined;
    const fallbackObjective = run.kickoffMessage?.trim() || managerOutputTask;
    const totalWorkers = outgoing.length;

    for (const [index, edge] of outgoing.entries()) {
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

      const fallbackTask = fallbackObjective
        ? [
            `Worker partition ${index + 1}/${totalWorkers}.`,
            `You are responsible only for worker '${worker.label}' (${worker.id}).`,
            `Objective: ${fallbackObjective}`,
            "Do not duplicate work assigned to other workers.",
          ].join(" ")
        : `Execute only the scoped task for worker '${worker.label}' (${worker.id}) and avoid duplicating other workers.`;

      this.store.addManagerTraceEntry(runId, {
        managerNodeId: managerNode.id,
        workerNodeId: worker.id,
        task:
          assignment?.task ||
          fallbackTask,
        reason:
          assignment?.reason ||
          `auto-partition fallback; relationType=${edge.relationType}; partition=${index + 1}/${totalWorkers}`,
      });
    }
  }

  private notifyManagersAboutSubordinateCompletion(
    runId: string,
    workerNodeId: string,
    status: "completed" | "failed" | "canceled",
  ): void {
    const run = this.store.getRunForExecution(runId);
    if (!run) {
      return;
    }

    const worker = run.nodes.find((node) => node.id === workerNodeId);
    if (!worker) {
      return;
    }

    const state = run.nodeStates[workerNodeId];
    const summary = state?.summary?.trim()
      || (state?.result?.output ? extractShortSummary(state.result.output) : undefined)
      || state?.lastError?.trim()
      || "No summary available.";
    const resultFiles = state?.artifacts?.resultFiles ?? [];

    const managerTargets = run.edges
      .filter(
        (edge) =>
          edge.fromNodeId === workerNodeId &&
          edge.relationType === "feedback",
      )
      .map((edge) => run.nodes.find((node) => node.id === edge.toNodeId))
      .filter((node): node is GraphNode => {
        if (!node) {
          return false;
        }
        return isManagerNode(node);
      });

    for (const manager of managerTargets) {
      this.store.addNodeMessage(
        run.graphId,
        manager.id,
        "system",
        [
          `Subordinate update: ${worker.label} (${worker.id})`,
          `status: ${status}`,
          `summary: ${summary}`,
          `resultFiles: ${resultFiles.length > 0 ? resultFiles.slice(0, 6).join(", ") : "none"}`,
        ].join("\n"),
        runId,
      );
    }
  }

  private publishRunSummaryToManagers(
    run: GraphRun,
    finalStatus: "completed" | "failed" | "canceled",
  ): void {
    const managers = run.nodes.filter((node) => isManagerNode(node));
    if (managers.length === 0) {
      return;
    }

    for (const manager of managers) {
      const subordinateEdges = run.edges.filter(
        (edge) => edge.toNodeId === manager.id && edge.relationType === "feedback",
      );
      if (subordinateEdges.length === 0) {
        continue;
      }

      const lines = subordinateEdges.map((edge) => {
        const worker = run.nodes.find((node) => node.id === edge.fromNodeId);
        if (!worker) {
          return `- unknown worker (${edge.fromNodeId}): no data`;
        }

        const state = run.nodeStates[worker.id];
        const status = state?.status ?? "unknown";
        const summary = state?.summary?.trim()
          || (state?.result?.output ? extractShortSummary(state.result.output, 220) : undefined)
          || state?.lastError?.trim()
          || "No summary available.";
        const resultFiles = state?.artifacts?.resultFiles ?? [];

        return `- ${worker.label} (${worker.id}) | status=${status} | summary=${summary} | resultFiles=${resultFiles.length > 0 ? resultFiles.slice(0, 4).join(",") : "none"}`;
      });

      this.store.addNodeMessage(
        run.graphId,
        manager.id,
        "system",
        [
          `Run ${run.runId} finished with status=${finalStatus}.`,
          "Subordinates summary:",
          ...lines,
        ].join("\n"),
        run.runId,
      );
    }
  }
}
