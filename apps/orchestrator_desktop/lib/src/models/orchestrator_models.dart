import 'dart:convert';

DateTime? _parseDateTime(dynamic value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry('$key', mapValue));
  }
  return null;
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

class BridgeHealth {
  const BridgeHealth({
    required this.healthy,
    required this.managedProcessRunning,
  });

  final bool healthy;
  final bool managedProcessRunning;

  factory BridgeHealth.fromJson(Map<String, dynamic> json) {
    return BridgeHealth(
      healthy: _asBool(json['healthy']),
      managedProcessRunning: _asBool(json['managedProcessRunning']),
    );
  }
}

class OrchestratorHealth {
  const OrchestratorHealth({
    required this.ok,
    required this.service,
    required this.mode,
    required this.runningTasks,
    required this.time,
    this.bridge,
  });

  final bool ok;
  final String service;
  final String mode;
  final int runningTasks;
  final DateTime? time;
  final BridgeHealth? bridge;

  factory OrchestratorHealth.fromJson(Map<String, dynamic> json) {
    final bridgeRaw = _asMap(json['bridge']);
    return OrchestratorHealth(
      ok: _asBool(json['ok']),
      service: _asString(json['service'], fallback: 'orchestrator'),
      mode: _asString(json['mode'], fallback: 'unknown'),
      runningTasks: _asInt(json['runningTasks']),
      time: _parseDateTime(json['time']),
      bridge: bridgeRaw == null ? null : BridgeHealth.fromJson(bridgeRaw),
    );
  }
}

class MinimalTaskInput {
  const MinimalTaskInput({
    this.task,
    this.cwd,
    required this.managerTimeoutMs,
    required this.workerTimeoutMs,
  });

  final String? task;
  final String? cwd;
  final int managerTimeoutMs;
  final int workerTimeoutMs;

  factory MinimalTaskInput.fromJson(Map<String, dynamic> json) {
    return MinimalTaskInput(
      task: _asString(json['task']).trim().isEmpty
          ? null
          : _asString(json['task']).trim(),
      cwd: _asString(json['cwd']).trim().isEmpty
          ? null
          : _asString(json['cwd']).trim(),
      managerTimeoutMs: _asInt(json['managerTimeoutMs']),
      workerTimeoutMs: _asInt(json['workerTimeoutMs']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (task != null) 'task': task,
      if (cwd != null) 'cwd': cwd,
      'managerTimeoutMs': managerTimeoutMs,
      'workerTimeoutMs': workerTimeoutMs,
    };
  }
}

class TaskTimelineEvent {
  const TaskTimelineEvent({
    required this.sequence,
    required this.at,
    required this.type,
    this.data,
  });

  final int sequence;
  final DateTime? at;
  final String type;
  final Map<String, dynamic>? data;

  factory TaskTimelineEvent.fromJson(Map<String, dynamic> json) {
    return TaskTimelineEvent(
      sequence: _asInt(json['sequence']),
      at: _parseDateTime(json['at']),
      type: _asString(json['type']),
      data: _asMap(json['data']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sequence': sequence,
      'at': at?.toIso8601String(),
      'type': type,
      if (data != null) 'data': data,
    };
  }
}

class OrchestratorTask {
  const OrchestratorTask({
    required this.id,
    required this.kind,
    required this.status,
    required this.input,
    required this.cancelRequested,
    required this.createdAt,
    required this.updatedAt,
    required this.timeline,
    this.startedAt,
    this.finishedAt,
    this.result,
    this.error,
  });

  final String id;
  final String kind;
  final String status;
  final MinimalTaskInput input;
  final bool cancelRequested;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final Map<String, dynamic>? result;
  final String? error;
  final List<TaskTimelineEvent> timeline;

  factory OrchestratorTask.fromJson(Map<String, dynamic> json) {
    final inputRaw = _asMap(json['input']) ?? const <String, dynamic>{};
    final timelineRaw = json['timeline'];
    final timeline = <TaskTimelineEvent>[];
    if (timelineRaw is List) {
      for (final item in timelineRaw) {
        final eventMap = _asMap(item);
        if (eventMap != null) {
          timeline.add(TaskTimelineEvent.fromJson(eventMap));
        }
      }
    }
    timeline.sort((a, b) => a.sequence.compareTo(b.sequence));

    return OrchestratorTask(
      id: _asString(json['id']),
      kind: _asString(json['kind'], fallback: 'minimal'),
      status: _asString(json['status']),
      input: MinimalTaskInput.fromJson(inputRaw),
      cancelRequested: _asBool(json['cancelRequested']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      startedAt: _parseDateTime(json['startedAt']),
      finishedAt: _parseDateTime(json['finishedAt']),
      result: _asMap(json['result']),
      error: _asString(json['error']).trim().isEmpty
          ? null
          : _asString(json['error']).trim(),
      timeline: timeline,
    );
  }

  OrchestratorTask copyWith({
    String? status,
    bool? cancelRequested,
    DateTime? updatedAt,
    DateTime? finishedAt,
    DateTime? startedAt,
    String? error,
    bool clearError = false,
    Map<String, dynamic>? result,
    bool clearResult = false,
    List<TaskTimelineEvent>? timeline,
  }) {
    return OrchestratorTask(
      id: id,
      kind: kind,
      status: status ?? this.status,
      input: input,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      result: clearResult ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
      timeline: timeline ?? this.timeline,
    );
  }
}

class TaskStreamEvent {
  const TaskStreamEvent({
    required this.taskId,
    required this.status,
    required this.cancelRequested,
    required this.event,
  });

  final String taskId;
  final String status;
  final bool cancelRequested;
  final TaskTimelineEvent event;

  factory TaskStreamEvent.fromJson(Map<String, dynamic> json) {
    return TaskStreamEvent(
      taskId: _asString(json['taskId']),
      status: _asString(json['status']),
      cancelRequested: _asBool(json['cancelRequested']),
      event: TaskTimelineEvent.fromJson(
        _asMap(json['event']) ?? const <String, dynamic>{},
      ),
    );
  }
}

class TaskSseMessage {
  const TaskSseMessage({required this.eventName, required this.data});

  final String eventName;
  final Map<String, dynamic> data;
}

class CreateTaskRequest {
  const CreateTaskRequest({
    this.task,
    this.cwd,
    this.managerTimeoutMs,
    this.workerTimeoutMs,
  });

  final String? task;
  final String? cwd;
  final int? managerTimeoutMs;
  final int? workerTimeoutMs;

  Map<String, dynamic> toJson() {
    return {
      if (task != null && task!.trim().isNotEmpty) 'task': task!.trim(),
      if (cwd != null && cwd!.trim().isNotEmpty) 'cwd': cwd!.trim(),
      if (managerTimeoutMs != null) 'managerTimeoutMs': managerTimeoutMs,
      if (workerTimeoutMs != null) 'workerTimeoutMs': workerTimeoutMs,
    };
  }
}

bool isTaskTerminal(String status) {
  return status == 'completed' || status == 'failed' || status == 'canceled';
}

String taskStatusLabel(String status) {
  switch (status) {
    case 'queued':
      return 'В очереди';
    case 'planning':
      return 'Планирование';
    case 'running':
      return 'Выполняется';
    case 'cancel_requested':
      return 'Запрошена отмена';
    case 'completed':
      return 'Завершено';
    case 'failed':
      return 'Ошибка';
    case 'canceled':
      return 'Отменено';
    default:
      return status;
  }
}

String prettyJson(Object? value) {
  if (value == null) {
    return '';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}
