import { randomUUID } from "node:crypto";

import { AgentRunner, RunResult } from "../types";

const DEFAULT_TEST_TASK = [
  "Create a minimal orchestration demo in docs/orchestrator-demo.",
  "The final result must contain two independent markdown files:",
  "1) setup-checklist.md with a short checklist for starting cli-bridge.",
  "2) api-checklist.md with a short checklist for testing POST /runs.",
  "Each file should have 5 bullet points and a short title.",
].join(" ");

interface WorkerAssignment {
  title: string;
  instructions: string;
}

interface ManagerPlan {
  goal: string;
  worker1: WorkerAssignment;
  worker2: WorkerAssignment;
  mergeNotes?: string;
}

export interface MinimalOrchestrationOptions {
  task?: string;
  cwd?: string;
  managerTimeoutMs: number;
  workerTimeoutMs: number;
  onProgress?: (event: OrchestrationProgressEvent) => void;
  shouldCancel?: () => boolean;
}

interface ManagerReport {
  prompt: string;
  result: RunResult;
  rawOutput: string;
  plan: ManagerPlan;
  fallbackUsed: boolean;
}

export interface WorkerRunReport {
  workerId: "qwen-1" | "qwen-2";
  agentId: "qwen";
  assignment: WorkerAssignment;
  prompt: string;
  result?: RunResult;
  error?: string;
}

export interface MinimalOrchestrationResult {
  runId: string;
  task: string;
  cwd?: string;
  success: boolean;
  manager: ManagerReport;
  workers: WorkerRunReport[];
}

export interface OrchestrationProgressEvent {
  phase:
    | "planning_started"
    | "planning_finished"
    | "workers_started"
    | "worker_started"
    | "worker_finished";
  at: string;
  workerId?: "qwen-1" | "qwen-2";
  info?: Record<string, unknown>;
}

export class OrchestrationCanceledError extends Error {
  constructor(message = "Orchestration canceled") {
    super(message);
    this.name = "OrchestrationCanceledError";
  }
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }
  return value as Record<string, unknown>;
}

function pickString(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === "string") {
      const normalized = value.trim();
      if (normalized) {
        return normalized;
      }
    }
  }
  return undefined;
}

function parseAssignment(value: unknown): WorkerAssignment | undefined {
  const record = asRecord(value);
  if (!record) {
    return undefined;
  }

  const title = pickString(record.title, record.name, record.task) ?? "Worker task";
  const instructions = pickString(
    record.instructions,
    record.details,
    record.prompt,
    record.task,
  );

  if (!instructions) {
    return undefined;
  }

  return {
    title,
    instructions,
  };
}

function parsePlanObject(value: unknown): ManagerPlan | undefined {
  const record = asRecord(value);
  if (!record) {
    return undefined;
  }

  const goal = pickString(record.goal, record.testGoal, record.objective);
  const mergeNotes = pickString(record.mergeNotes, record.merge, record.summaryNotes);

  let worker1 = parseAssignment(record.worker1);
  let worker2 = parseAssignment(record.worker2);

  const workers = record.workers;
  if ((!worker1 || !worker2) && Array.isArray(workers) && workers.length >= 2) {
    worker1 = worker1 ?? parseAssignment(workers[0]);
    worker2 = worker2 ?? parseAssignment(workers[1]);
  }

  if (!worker1 || !worker2) {
    return undefined;
  }

  return {
    goal: goal ?? "Split and execute the user task in parallel",
    worker1,
    worker2,
    mergeNotes,
  };
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

      if (char === "\"") {
        inString = false;
      }
      continue;
    }

    if (char === "\"") {
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

function parseManagerPlan(rawOutput: string): ManagerPlan | undefined {
  const text = rawOutput.trim();
  if (!text) {
    return undefined;
  }

  const candidates: string[] = [text];

  const fenced = [...text.matchAll(/```(?:json)?\s*([\s\S]*?)```/gi)];
  for (const match of fenced) {
    const candidate = match[1]?.trim();
    if (candidate) {
      candidates.push(candidate);
    }
  }

  const firstObject = extractFirstJsonObject(text);
  if (firstObject) {
    candidates.push(firstObject);
  }

  const seen = new Set<string>();
  for (const candidate of candidates) {
    if (seen.has(candidate)) {
      continue;
    }
    seen.add(candidate);

    try {
      const parsed = JSON.parse(candidate);
      const plan = parsePlanObject(parsed);
      if (plan) {
        return plan;
      }
    } catch {
      // Continue trying other candidates.
    }
  }

  return undefined;
}

function buildFallbackPlan(task: string): ManagerPlan {
  return {
    goal: task,
    worker1: {
      title: "Create setup checklist",
      instructions: [
        "Create or overwrite docs/orchestrator-demo/setup-checklist.md.",
        "Add a title and exactly 5 bullet points describing how to start cli-bridge locally.",
        "Keep it concise and practical.",
      ].join(" "),
    },
    worker2: {
      title: "Create API checklist",
      instructions: [
        "Create or overwrite docs/orchestrator-demo/api-checklist.md.",
        "Add a title and exactly 5 bullet points describing how to test POST /runs locally.",
        "Keep it concise and practical.",
      ].join(" "),
    },
    mergeNotes:
      "Both files should be ready for a quick manual review after the orchestration run.",
  };
}

function buildManagerPrompt(task: string): string {
  const schema =
    "{\"goal\":\"string\",\"worker1\":{\"title\":\"string\",\"instructions\":\"string\"},\"worker2\":{\"title\":\"string\",\"instructions\":\"string\"},\"mergeNotes\":\"string\"}";

  return [
    "You are Codex acting as a manager agent in a minimal orchestrator.",
    "Split the user task into exactly two parallel subtasks for two Qwen workers.",
    "Return strict JSON only with no markdown and no extra text.",
    `JSON schema: ${schema}.`,
    "Requirements: worker1 and worker2 must be independent and runnable in parallel.",
    "If files are involved, provide exact file paths.",
    "Instructions should be specific and executable via CLI.",
    `User task: ${task}`,
  ].join(" ");
}

function buildWorkerPrompt(
  workerId: "qwen-1" | "qwen-2",
  task: string,
  assignment: WorkerAssignment,
  mergeNotes?: string,
): string {
  const sections = [
    `You are ${workerId}, a worker agent in a minimal orchestrator.`,
    `Global task: ${task}.`,
    `Your subtask title: ${assignment.title}.`,
    `Your subtask instructions: ${assignment.instructions}.`,
    "Execute the requested changes now in the current working directory.",
    "Do not wait for confirmation.",
  ];

  if (mergeNotes) {
    sections.push(`Manager merge notes: ${mergeNotes}.`);
  }

  sections.push("When finished, reply with a short plain-text report including changed file paths.");
  return sections.join(" ");
}

export async function runMinimalOrchestration(
  runner: AgentRunner,
  options: MinimalOrchestrationOptions,
): Promise<MinimalOrchestrationResult> {
  const task = options.task?.trim() || DEFAULT_TEST_TASK;
  const runId = randomUUID();
  const emit = (event: Omit<OrchestrationProgressEvent, "at">): void => {
    options.onProgress?.({
      ...event,
      at: new Date().toISOString(),
    });
  };
  const guardCanceled = (): void => {
    if (options.shouldCancel?.()) {
      throw new OrchestrationCanceledError();
    }
  };

  guardCanceled();
  emit({
    phase: "planning_started",
    info: {
      runId,
    },
  });
  const managerPrompt = buildManagerPrompt(task);
  const managerResult = await runner.run("codex", managerPrompt, {
    cwd: options.cwd,
    timeoutMs: options.managerTimeoutMs,
  });

  const parsedPlan = parseManagerPlan(managerResult.output);
  const fallbackPlan = buildFallbackPlan(task);
  const plan = parsedPlan ?? fallbackPlan;
  const fallbackUsed = !parsedPlan;
  emit({
    phase: "planning_finished",
    info: {
      fallbackUsed,
    },
  });

  guardCanceled();
  const worker1Prompt = buildWorkerPrompt("qwen-1", task, plan.worker1, plan.mergeNotes);
  const worker2Prompt = buildWorkerPrompt("qwen-2", task, plan.worker2, plan.mergeNotes);
  emit({
    phase: "workers_started",
    info: {
      workers: 2,
    },
  });

  const [worker1, worker2] = await Promise.allSettled([
    (async () => {
      emit({
        phase: "worker_started",
        workerId: "qwen-1",
      });
      const value = await runner.run("qwen", worker1Prompt, {
        cwd: options.cwd,
        timeoutMs: options.workerTimeoutMs,
      });
      emit({
        phase: "worker_finished",
        workerId: "qwen-1",
        info: {
          timedOut: value.timedOut,
          durationMs: value.durationMs,
        },
      });
      return value;
    })(),
    (async () => {
      emit({
        phase: "worker_started",
        workerId: "qwen-2",
      });
      const value = await runner.run("qwen", worker2Prompt, {
        cwd: options.cwd,
        timeoutMs: options.workerTimeoutMs,
      });
      emit({
        phase: "worker_finished",
        workerId: "qwen-2",
        info: {
          timedOut: value.timedOut,
          durationMs: value.durationMs,
        },
      });
      return value;
    })(),
  ]);

  const reports: WorkerRunReport[] = [
    {
      workerId: "qwen-1",
      agentId: "qwen",
      assignment: plan.worker1,
      prompt: worker1Prompt,
      result: worker1.status === "fulfilled" ? worker1.value : undefined,
      error: worker1.status === "rejected" ? String(worker1.reason) : undefined,
    },
    {
      workerId: "qwen-2",
      agentId: "qwen",
      assignment: plan.worker2,
      prompt: worker2Prompt,
      result: worker2.status === "fulfilled" ? worker2.value : undefined,
      error: worker2.status === "rejected" ? String(worker2.reason) : undefined,
    },
  ];
  for (const report of reports) {
    if (report.error) {
      emit({
        phase: "worker_finished",
        workerId: report.workerId,
        info: {
          error: report.error,
        },
      });
    }
  }

  const success = reports.every(
    (report) => !report.error && report.result && !report.result.timedOut,
  );

  return {
    runId,
    task,
    cwd: options.cwd,
    success,
    manager: {
      prompt: managerPrompt,
      result: managerResult,
      rawOutput: managerResult.output,
      plan,
      fallbackUsed,
    },
    workers: reports,
  };
}
