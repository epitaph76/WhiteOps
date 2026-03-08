import { randomUUID } from "node:crypto";
import { EventEmitter } from "node:events";

import {
  MinimalOrchestrationResult,
  OrchestrationProgressEvent,
} from "../orchestration/minimal-orchestration";

const MAX_TIMELINE = 250;

export type TaskStatus =
  | "queued"
  | "planning"
  | "running"
  | "cancel_requested"
  | "completed"
  | "failed"
  | "canceled";

export interface MinimalTaskInput {
  task?: string;
  cwd?: string;
  managerTimeoutMs: number;
  workerTimeoutMs: number;
}

export interface TaskTimelineEvent {
  sequence: number;
  at: string;
  type: string;
  data?: Record<string, unknown>;
}

export interface TaskSnapshot {
  id: string;
  kind: "minimal";
  status: TaskStatus;
  input: MinimalTaskInput;
  cancelRequested: boolean;
  createdAt: string;
  updatedAt: string;
  startedAt?: string;
  finishedAt?: string;
  result?: MinimalOrchestrationResult;
  error?: string;
  timeline: TaskTimelineEvent[];
}

export interface TaskStreamEvent {
  taskId: string;
  status: TaskStatus;
  cancelRequested: boolean;
  event: TaskTimelineEvent;
}

interface TaskRecord extends TaskSnapshot {
  nextSequence: number;
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

export class TaskStore {
  private readonly tasks = new Map<string, TaskRecord>();
  private readonly emitter = new EventEmitter();

  createTask(input: MinimalTaskInput): TaskSnapshot {
    const now = new Date().toISOString();
    const id = randomUUID();
    const record: TaskRecord = {
      id,
      kind: "minimal",
      status: "queued",
      input,
      cancelRequested: false,
      createdAt: now,
      updatedAt: now,
      timeline: [],
      nextSequence: 1,
    };

    this.tasks.set(id, record);
    this.pushTimeline(record, "task_created", {
      kind: "minimal",
    });
    return this.toSnapshot(record);
  }

  listTasks(limit = 50): TaskSnapshot[] {
    const clampedLimit = Math.max(1, Math.min(limit, 200));
    return [...this.tasks.values()]
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .slice(0, clampedLimit)
      .map((record) => this.toSnapshot(record));
  }

  getTask(taskId: string): TaskSnapshot | undefined {
    const record = this.tasks.get(taskId);
    return record ? this.toSnapshot(record) : undefined;
  }

  requestCancel(taskId: string): TaskSnapshot | undefined {
    const record = this.tasks.get(taskId);
    if (!record) {
      return undefined;
    }

    if (record.status === "completed" || record.status === "failed" || record.status === "canceled") {
      return this.toSnapshot(record);
    }

    record.cancelRequested = true;
    if (record.status === "queued") {
      record.status = "canceled";
      record.finishedAt = new Date().toISOString();
      this.pushTimeline(record, "task_canceled", {
        reason: "Canceled before start",
      });
      return this.toSnapshot(record);
    }

    record.status = "cancel_requested";
    this.pushTimeline(record, "cancel_requested", {
      status: record.status,
    });
    return this.toSnapshot(record);
  }

  shouldCancel(taskId: string): boolean {
    const record = this.tasks.get(taskId);
    return Boolean(record?.cancelRequested);
  }

  markPlanning(taskId: string): void {
    const record = this.getRequired(taskId);
    const now = new Date().toISOString();
    if (!record.startedAt) {
      record.startedAt = now;
    }
    record.status = record.cancelRequested ? "cancel_requested" : "planning";
    this.pushTimeline(record, "planning_started");
  }

  markRunning(taskId: string): void {
    const record = this.getRequired(taskId);
    record.status = record.cancelRequested ? "cancel_requested" : "running";
    this.pushTimeline(record, "workers_running");
  }

  addProgress(taskId: string, event: OrchestrationProgressEvent): void {
    const record = this.getRequired(taskId);
    this.pushTimeline(record, `progress_${event.phase}`, {
      workerId: event.workerId,
      info: event.info,
    });
  }

  finishCompleted(taskId: string, result: MinimalOrchestrationResult): void {
    const record = this.getRequired(taskId);
    record.result = result;
    record.status = "completed";
    record.finishedAt = new Date().toISOString();
    this.pushTimeline(record, "task_completed", {
      success: result.success,
    });
  }

  finishCanceled(taskId: string, reason?: string): void {
    const record = this.getRequired(taskId);
    record.status = "canceled";
    record.finishedAt = new Date().toISOString();
    this.pushTimeline(record, "task_canceled", {
      reason: reason ?? "Canceled by user",
    });
  }

  finishFailed(taskId: string, error: string): void {
    const record = this.getRequired(taskId);
    record.error = error;
    record.status = "failed";
    record.finishedAt = new Date().toISOString();
    this.pushTimeline(record, "task_failed", {
      error,
    });
  }

  subscribe(taskId: string, listener: (event: TaskStreamEvent) => void): () => void {
    const channel = this.getChannel(taskId);
    this.emitter.on(channel, listener);
    return () => {
      this.emitter.off(channel, listener);
    };
  }

  private pushTimeline(
    record: TaskRecord,
    type: string,
    data?: Record<string, unknown>,
  ): void {
    const timelineEvent: TaskTimelineEvent = {
      sequence: record.nextSequence,
      at: new Date().toISOString(),
      type,
      data,
    };
    record.nextSequence += 1;
    record.updatedAt = timelineEvent.at;
    record.timeline.push(timelineEvent);
    if (record.timeline.length > MAX_TIMELINE) {
      record.timeline.shift();
    }

    this.emitter.emit(this.getChannel(record.id), {
      taskId: record.id,
      status: record.status,
      cancelRequested: record.cancelRequested,
      event: timelineEvent,
    } satisfies TaskStreamEvent);
  }

  private getRequired(taskId: string): TaskRecord {
    const record = this.tasks.get(taskId);
    if (!record) {
      throw new Error(`Task ${taskId} not found`);
    }
    return record;
  }

  private getChannel(taskId: string): string {
    return `task:${taskId}`;
  }

  private toSnapshot(record: TaskRecord): TaskSnapshot {
    const { nextSequence, ...snapshot } = record;
    void nextSequence;
    return clone(snapshot);
  }
}
