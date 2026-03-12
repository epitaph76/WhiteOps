import 'dart:convert';

DateTime? _parseDateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry('$key', mapValue));
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value.cast<Object?>();
  }
  return const [];
}

String _asString(Object? value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

bool _asBool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

class GraphNodeConfigModel {
  const GraphNodeConfigModel({
    required this.agentId,
    required this.role,
    this.fullAccess = false,
    this.feedbackToManagerEnabled,
    this.prompt,
    this.cwd,
    this.timeoutMs,
    this.maxRetries,
    this.retryDelayMs,
    this.metadata,
  });

  final String agentId;
  final String role;
  final bool fullAccess;
  final bool? feedbackToManagerEnabled;
  final String? prompt;
  final String? cwd;
  final int? timeoutMs;
  final int? maxRetries;
  final int? retryDelayMs;
  final Map<String, dynamic>? metadata;

  factory GraphNodeConfigModel.fromJson(Map<String, dynamic> json) {
    return GraphNodeConfigModel(
      agentId: _asString(json['agentId'], fallback: 'qwen'),
      role: _asString(json['role'], fallback: 'worker'),
      fullAccess: _asBool(json['fullAccess']),
      feedbackToManagerEnabled: json['feedbackToManagerEnabled'] == null
          ? null
          : _asBool(json['feedbackToManagerEnabled']),
      prompt: _asString(json['prompt']).trim().isEmpty
          ? null
          : _asString(json['prompt']).trim(),
      cwd: _asString(json['cwd']).trim().isEmpty
          ? null
          : _asString(json['cwd']).trim(),
      timeoutMs: json['timeoutMs'] == null ? null : _asInt(json['timeoutMs']),
      maxRetries: json['maxRetries'] == null
          ? null
          : _asInt(json['maxRetries']),
      retryDelayMs: json['retryDelayMs'] == null
          ? null
          : _asInt(json['retryDelayMs']),
      metadata: _asMap(json['metadata']),
    );
  }

  GraphNodeConfigModel copyWith({
    String? agentId,
    String? role,
    bool? fullAccess,
    bool? feedbackToManagerEnabled,
    bool clearFeedbackToManagerEnabled = false,
    String? prompt,
    bool clearPrompt = false,
    String? cwd,
    bool clearCwd = false,
    int? timeoutMs,
    bool clearTimeoutMs = false,
    int? maxRetries,
    bool clearMaxRetries = false,
    int? retryDelayMs,
    bool clearRetryDelayMs = false,
    Map<String, dynamic>? metadata,
    bool clearMetadata = false,
  }) {
    return GraphNodeConfigModel(
      agentId: agentId ?? this.agentId,
      role: role ?? this.role,
      fullAccess: fullAccess ?? this.fullAccess,
      feedbackToManagerEnabled: clearFeedbackToManagerEnabled
          ? null
          : (feedbackToManagerEnabled ?? this.feedbackToManagerEnabled),
      prompt: clearPrompt ? null : (prompt ?? this.prompt),
      cwd: clearCwd ? null : (cwd ?? this.cwd),
      timeoutMs: clearTimeoutMs ? null : (timeoutMs ?? this.timeoutMs),
      maxRetries: clearMaxRetries ? null : (maxRetries ?? this.maxRetries),
      retryDelayMs: clearRetryDelayMs
          ? null
          : (retryDelayMs ?? this.retryDelayMs),
      metadata: clearMetadata ? null : (metadata ?? this.metadata),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'agentId': agentId,
      'role': role,
      'fullAccess': fullAccess,
      if (feedbackToManagerEnabled != null)
        'feedbackToManagerEnabled': feedbackToManagerEnabled,
      if (prompt != null && prompt!.trim().isNotEmpty) 'prompt': prompt!.trim(),
      if (cwd != null && cwd!.trim().isNotEmpty) 'cwd': cwd!.trim(),
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
      if (maxRetries != null && maxRetries! > 0) 'maxRetries': maxRetries,
      if (retryDelayMs != null) 'retryDelayMs': retryDelayMs,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

class GraphNodeModel {
  const GraphNodeModel({
    required this.id,
    required this.type,
    required this.label,
    required this.x,
    required this.y,
    required this.config,
  });

  final String id;
  final String type;
  final String label;
  final double x;
  final double y;
  final GraphNodeConfigModel config;

  factory GraphNodeModel.fromJson(Map<String, dynamic> json) {
    final position = _asMap(json['position']) ?? const <String, dynamic>{};
    return GraphNodeModel(
      id: _asString(json['id']),
      type: _asString(json['type'], fallback: 'worker'),
      label: _asString(json['label'], fallback: 'Узел'),
      x: _asDouble(position['x']),
      y: _asDouble(position['y']),
      config: GraphNodeConfigModel.fromJson(
        _asMap(json['config']) ?? const <String, dynamic>{},
      ),
    );
  }

  GraphNodeModel copyWith({
    String? id,
    String? type,
    String? label,
    double? x,
    double? y,
    GraphNodeConfigModel? config,
  }) {
    return GraphNodeModel(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      x: x ?? this.x,
      y: y ?? this.y,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'label': label,
      'position': {'x': x, 'y': y},
      'config': config.toJson(),
    };
  }
}

class GraphEdgeModel {
  const GraphEdgeModel({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.relationType,
  });

  final String id;
  final String fromNodeId;
  final String toNodeId;
  final String relationType;

  factory GraphEdgeModel.fromJson(Map<String, dynamic> json) {
    return GraphEdgeModel(
      id: _asString(json['id']),
      fromNodeId: _asString(json['fromNodeId']),
      toNodeId: _asString(json['toNodeId']),
      relationType: _asString(json['relationType'], fallback: 'dependency'),
    );
  }

  GraphEdgeModel copyWith({String? relationType}) {
    return GraphEdgeModel(
      id: id,
      fromNodeId: fromNodeId,
      toNodeId: toNodeId,
      relationType: relationType ?? this.relationType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
      'relationType': relationType,
    };
  }
}

class GraphRevisionModel {
  const GraphRevisionModel({
    required this.revision,
    required this.createdAt,
    required this.createdBy,
    required this.nodes,
    required this.edges,
  });

  final int revision;
  final DateTime? createdAt;
  final String createdBy;
  final List<GraphNodeModel> nodes;
  final List<GraphEdgeModel> edges;

  factory GraphRevisionModel.fromJson(Map<String, dynamic> json) {
    final nodeItems = <GraphNodeModel>[];
    for (final raw in _asList(json['nodes'])) {
      final map = _asMap(raw);
      if (map != null) {
        nodeItems.add(GraphNodeModel.fromJson(map));
      }
    }

    final edgeItems = <GraphEdgeModel>[];
    for (final raw in _asList(json['edges'])) {
      final map = _asMap(raw);
      if (map != null) {
        edgeItems.add(GraphEdgeModel.fromJson(map));
      }
    }

    return GraphRevisionModel(
      revision: _asInt(json['revision']),
      createdAt: _parseDateTime(json['createdAt']),
      createdBy: _asString(json['createdBy']),
      nodes: nodeItems,
      edges: edgeItems,
    );
  }
}

class OrchestrationGraphModel {
  const OrchestrationGraphModel({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    required this.latestRevision,
    required this.revisionHistory,
    required this.revision,
  });

  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int latestRevision;
  final List<int> revisionHistory;
  final GraphRevisionModel revision;

  factory OrchestrationGraphModel.fromJson(Map<String, dynamic> json) {
    final history = <int>[];
    for (final value in _asList(json['revisionHistory'])) {
      if (value is int) {
        history.add(value);
      } else if (value is num) {
        history.add(value.toInt());
      }
    }

    return OrchestrationGraphModel(
      id: _asString(json['id']),
      name: _asString(json['name'], fallback: 'Схема без названия'),
      description: _asString(json['description']).trim().isEmpty
          ? null
          : _asString(json['description']).trim(),
      ownerId: _asString(json['ownerId']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      latestRevision: _asInt(json['latestRevision']),
      revisionHistory: history,
      revision: GraphRevisionModel.fromJson(
        _asMap(json['revision']) ?? const <String, dynamic>{},
      ),
    );
  }

  GraphUpsertRequest toUpsertRequest() {
    return GraphUpsertRequest(
      name: name,
      description: description,
      nodes: revision.nodes,
      edges: revision.edges,
    );
  }
}

class GraphValidationResultModel {
  const GraphValidationResultModel({
    required this.valid,
    required this.errors,
    required this.warnings,
    required this.topologicalOrder,
  });

  final bool valid;
  final List<String> errors;
  final List<String> warnings;
  final List<String> topologicalOrder;

  factory GraphValidationResultModel.fromJson(Map<String, dynamic> json) {
    final errors = _asList(
      json['errors'],
    ).map((item) => _asString(item)).where((item) => item.isNotEmpty).toList();
    final warnings = _asList(
      json['warnings'],
    ).map((item) => _asString(item)).where((item) => item.isNotEmpty).toList();
    final order = _asList(
      json['topologicalOrder'],
    ).map((item) => _asString(item)).where((item) => item.isNotEmpty).toList();

    return GraphValidationResultModel(
      valid: _asBool(json['valid']),
      errors: errors,
      warnings: warnings,
      topologicalOrder: order,
    );
  }
}

class GraphUpsertRequest {
  const GraphUpsertRequest({
    required this.name,
    this.description,
    required this.nodes,
    required this.edges,
  });

  final String name;
  final String? description;
  final List<GraphNodeModel> nodes;
  final List<GraphEdgeModel> edges;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null && description!.trim().isNotEmpty)
        'description': description!.trim(),
      'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
      'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
    };
  }
}

class GraphRunNodeStateModel {
  const GraphRunNodeStateModel({
    required this.nodeId,
    required this.status,
    required this.attempts,
    this.lastPrompt,
    this.startedAt,
    this.finishedAt,
    this.lastError,
    this.result,
    this.artifacts,
  });

  final String nodeId;
  final String status;
  final int attempts;
  final String? lastPrompt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? lastError;
  final Map<String, dynamic>? result;
  final Map<String, dynamic>? artifacts;

  factory GraphRunNodeStateModel.fromJson(Map<String, dynamic> json) {
    return GraphRunNodeStateModel(
      nodeId: _asString(json['nodeId']),
      status: _asString(json['status'], fallback: 'pending'),
      attempts: _asInt(json['attempts']),
      lastPrompt: _asString(json['lastPrompt']).trim().isEmpty
          ? null
          : _asString(json['lastPrompt']).trim(),
      startedAt: _parseDateTime(json['startedAt']),
      finishedAt: _parseDateTime(json['finishedAt']),
      lastError: _asString(json['lastError']).trim().isEmpty
          ? null
          : _asString(json['lastError']).trim(),
      result: _asMap(json['result']),
      artifacts: _asMap(json['artifacts']),
    );
  }

  GraphRunNodeStateModel copyWith({
    String? status,
    int? attempts,
    String? lastPrompt,
    bool clearLastPrompt = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    String? lastError,
    bool clearLastError = false,
    Map<String, dynamic>? result,
    bool clearResult = false,
    Map<String, dynamic>? artifacts,
    bool clearArtifacts = false,
  }) {
    return GraphRunNodeStateModel(
      nodeId: nodeId,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      lastPrompt: clearLastPrompt ? null : (lastPrompt ?? this.lastPrompt),
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      finishedAt: clearFinishedAt ? null : (finishedAt ?? this.finishedAt),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      result: clearResult ? null : (result ?? this.result),
      artifacts: clearArtifacts ? null : (artifacts ?? this.artifacts),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodeId': nodeId,
      'status': status,
      'attempts': attempts,
      if (lastPrompt != null && lastPrompt!.trim().isNotEmpty)
        'lastPrompt': lastPrompt!.trim(),
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
      if (lastError != null && lastError!.trim().isNotEmpty)
        'lastError': lastError!.trim(),
      if (result != null) 'result': result,
      if (artifacts != null) 'artifacts': artifacts,
    };
  }
}

class ManagerTraceEntryModel {
  const ManagerTraceEntryModel({
    required this.id,
    required this.runId,
    required this.managerNodeId,
    required this.workerNodeId,
    required this.task,
    required this.reason,
    required this.confirmationStatus,
    required this.assignedAt,
    this.confirmedAt,
    this.note,
  });

  final String id;
  final String runId;
  final String managerNodeId;
  final String workerNodeId;
  final String task;
  final String reason;
  final String confirmationStatus;
  final DateTime? assignedAt;
  final DateTime? confirmedAt;
  final String? note;

  factory ManagerTraceEntryModel.fromJson(Map<String, dynamic> json) {
    return ManagerTraceEntryModel(
      id: _asString(json['id']),
      runId: _asString(json['runId']),
      managerNodeId: _asString(json['managerNodeId']),
      workerNodeId: _asString(json['workerNodeId']),
      task: _asString(json['task']),
      reason: _asString(json['reason']),
      confirmationStatus: _asString(
        json['confirmationStatus'],
        fallback: 'pending',
      ),
      assignedAt: _parseDateTime(json['assignedAt']),
      confirmedAt: _parseDateTime(json['confirmedAt']),
      note: _asString(json['note']).trim().isEmpty
          ? null
          : _asString(json['note']).trim(),
    );
  }
}

class GraphRunEventModel {
  const GraphRunEventModel({
    required this.sequence,
    required this.type,
    required this.runId,
    required this.graphId,
    required this.graphRevision,
    required this.at,
    this.nodeId,
    this.data,
  });

  final int sequence;
  final String type;
  final String runId;
  final String graphId;
  final int graphRevision;
  final DateTime? at;
  final String? nodeId;
  final Map<String, dynamic>? data;

  factory GraphRunEventModel.fromJson(Map<String, dynamic> json) {
    return GraphRunEventModel(
      sequence: _asInt(json['sequence']),
      type: _asString(json['type']),
      runId: _asString(json['runId']),
      graphId: _asString(json['graphId']),
      graphRevision: _asInt(json['graphRevision']),
      at: _parseDateTime(json['at']),
      nodeId: _asString(json['nodeId']).trim().isEmpty
          ? null
          : _asString(json['nodeId']).trim(),
      data: _asMap(json['data']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sequence': sequence,
      'type': type,
      'runId': runId,
      'graphId': graphId,
      'graphRevision': graphRevision,
      if (at != null) 'at': at!.toIso8601String(),
      if (nodeId != null) 'nodeId': nodeId,
      if (data != null) 'data': data,
    };
  }
}

class GraphRunModel {
  const GraphRunModel({
    required this.runId,
    required this.graphId,
    required this.graphRevision,
    required this.requestedBy,
    required this.status,
    required this.cancelRequested,
    required this.createdAt,
    required this.updatedAt,
    this.startedAt,
    this.finishedAt,
    this.error,
    required this.nodes,
    required this.edges,
    required this.nodeStates,
    required this.managerTrace,
    required this.events,
  });

  final String runId;
  final String graphId;
  final int graphRevision;
  final String requestedBy;
  final String status;
  final bool cancelRequested;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;
  final List<GraphNodeModel> nodes;
  final List<GraphEdgeModel> edges;
  final Map<String, GraphRunNodeStateModel> nodeStates;
  final List<ManagerTraceEntryModel> managerTrace;
  final List<GraphRunEventModel> events;

  factory GraphRunModel.fromJson(Map<String, dynamic> json) {
    final nodeItems = <GraphNodeModel>[];
    for (final raw in _asList(json['nodes'])) {
      final map = _asMap(raw);
      if (map != null) {
        nodeItems.add(GraphNodeModel.fromJson(map));
      }
    }

    final edgeItems = <GraphEdgeModel>[];
    for (final raw in _asList(json['edges'])) {
      final map = _asMap(raw);
      if (map != null) {
        edgeItems.add(GraphEdgeModel.fromJson(map));
      }
    }

    final states = <String, GraphRunNodeStateModel>{};
    final nodeStatesRaw =
        _asMap(json['nodeStates']) ?? const <String, dynamic>{};
    nodeStatesRaw.forEach((key, value) {
      final map = _asMap(value);
      if (map != null) {
        states[key] = GraphRunNodeStateModel.fromJson(map);
      }
    });

    final trace = <ManagerTraceEntryModel>[];
    for (final raw in _asList(json['managerTrace'])) {
      final map = _asMap(raw);
      if (map != null) {
        trace.add(ManagerTraceEntryModel.fromJson(map));
      }
    }

    final events = <GraphRunEventModel>[];
    for (final raw in _asList(json['events'])) {
      final map = _asMap(raw);
      if (map != null) {
        events.add(GraphRunEventModel.fromJson(map));
      }
    }

    events.sort((a, b) => a.sequence.compareTo(b.sequence));

    return GraphRunModel(
      runId: _asString(json['runId']),
      graphId: _asString(json['graphId']),
      graphRevision: _asInt(json['graphRevision']),
      requestedBy: _asString(json['requestedBy']),
      status: _asString(json['status'], fallback: 'queued'),
      cancelRequested: _asBool(json['cancelRequested']),
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
      startedAt: _parseDateTime(json['startedAt']),
      finishedAt: _parseDateTime(json['finishedAt']),
      error: _asString(json['error']).trim().isEmpty
          ? null
          : _asString(json['error']).trim(),
      nodes: nodeItems,
      edges: edgeItems,
      nodeStates: states,
      managerTrace: trace,
      events: events,
    );
  }

  GraphRunModel copyWith({
    String? status,
    bool? cancelRequested,
    DateTime? updatedAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
    bool clearError = false,
    Map<String, GraphRunNodeStateModel>? nodeStates,
    List<ManagerTraceEntryModel>? managerTrace,
    List<GraphRunEventModel>? events,
  }) {
    return GraphRunModel(
      runId: runId,
      graphId: graphId,
      graphRevision: graphRevision,
      requestedBy: requestedBy,
      status: status ?? this.status,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      error: clearError ? null : (error ?? this.error),
      nodes: nodes,
      edges: edges,
      nodeStates: nodeStates ?? this.nodeStates,
      managerTrace: managerTrace ?? this.managerTrace,
      events: events ?? this.events,
    );
  }
}

class GraphRunStreamEventModel {
  const GraphRunStreamEventModel({
    required this.runId,
    required this.status,
    required this.cancelRequested,
    required this.event,
  });

  final String runId;
  final String status;
  final bool cancelRequested;
  final GraphRunEventModel event;

  factory GraphRunStreamEventModel.fromJson(Map<String, dynamic> json) {
    return GraphRunStreamEventModel(
      runId: _asString(json['runId']),
      status: _asString(json['status'], fallback: 'queued'),
      cancelRequested: _asBool(json['cancelRequested']),
      event: GraphRunEventModel.fromJson(
        _asMap(json['event']) ?? const <String, dynamic>{},
      ),
    );
  }
}

class GraphSseMessage {
  const GraphSseMessage({required this.eventName, required this.data});

  final String eventName;
  final Map<String, dynamic> data;
}

class NodeChatMessageModel {
  const NodeChatMessageModel({
    required this.id,
    required this.graphId,
    required this.nodeId,
    this.runId,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String graphId;
  final String nodeId;
  final String? runId;
  final String role;
  final String text;
  final DateTime? createdAt;

  factory NodeChatMessageModel.fromJson(Map<String, dynamic> json) {
    return NodeChatMessageModel(
      id: _asString(json['id']),
      graphId: _asString(json['graphId']),
      nodeId: _asString(json['nodeId']),
      runId: _asString(json['runId']).trim().isEmpty
          ? null
          : _asString(json['runId']).trim(),
      role: _asString(json['role'], fallback: 'assistant'),
      text: _asString(json['text']),
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'graphId': graphId,
      'nodeId': nodeId,
      if (runId != null) 'runId': runId,
      'role': role,
      'text': text,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}

class NodeLogEntryModel {
  const NodeLogEntryModel({
    required this.id,
    required this.graphId,
    required this.nodeId,
    this.runId,
    required this.stream,
    required this.chunk,
    required this.sequence,
    required this.createdAt,
  });

  final String id;
  final String graphId;
  final String nodeId;
  final String? runId;
  final String stream;
  final String chunk;
  final int sequence;
  final DateTime? createdAt;

  factory NodeLogEntryModel.fromJson(Map<String, dynamic> json) {
    return NodeLogEntryModel(
      id: _asString(json['id']),
      graphId: _asString(json['graphId']),
      nodeId: _asString(json['nodeId']),
      runId: _asString(json['runId']).trim().isEmpty
          ? null
          : _asString(json['runId']).trim(),
      stream: _asString(json['stream'], fallback: 'system'),
      chunk: _asString(json['chunk']),
      sequence: _asInt(json['sequence']),
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'graphId': graphId,
      'nodeId': nodeId,
      if (runId != null) 'runId': runId,
      'stream': stream,
      'chunk': chunk,
      'sequence': sequence,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    };
  }
}

class NodeChatRequestModel {
  const NodeChatRequestModel({
    required this.message,
    this.graphId,
    this.runId,
    this.timeoutMs,
    this.cwd,
  });

  final String message;
  final String? graphId;
  final String? runId;
  final int? timeoutMs;
  final String? cwd;

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      if (graphId != null && graphId!.trim().isNotEmpty) 'graphId': graphId,
      if (runId != null && runId!.trim().isNotEmpty) 'runId': runId,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
      if (cwd != null && cwd!.trim().isNotEmpty) 'cwd': cwd,
    };
  }
}

class NodeChatResponseModel {
  const NodeChatResponseModel({
    required this.userMessage,
    required this.assistantMessage,
    required this.result,
  });

  final NodeChatMessageModel userMessage;
  final NodeChatMessageModel assistantMessage;
  final Map<String, dynamic> result;

  factory NodeChatResponseModel.fromJson(Map<String, dynamic> json) {
    return NodeChatResponseModel(
      userMessage: NodeChatMessageModel.fromJson(
        _asMap(json['userMessage']) ?? const <String, dynamic>{},
      ),
      assistantMessage: NodeChatMessageModel.fromJson(
        _asMap(json['assistantMessage']) ?? const <String, dynamic>{},
      ),
      result: _asMap(json['result']) ?? const <String, dynamic>{},
    );
  }
}

bool isGraphRunTerminal(String status) {
  return status == 'completed' || status == 'failed' || status == 'canceled';
}

bool isNodeExecutionTerminal(String status) {
  return status == 'completed' ||
      status == 'failed' ||
      status == 'canceled' ||
      status == 'skipped';
}

String graphRunStatusLabel(String status) {
  switch (status) {
    case 'queued':
      return 'В очереди';
    case 'running':
      return 'Выполняется';
    case 'completed':
      return 'Завершен';
    case 'failed':
      return 'Ошибка';
    case 'canceled':
      return 'Остановлен';
    default:
      return status;
  }
}

String nodeExecutionStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Ожидание';
    case 'ready':
      return 'Готов';
    case 'running':
      return 'Выполняется';
    case 'retrying':
      return 'Повтор';
    case 'completed':
      return 'Завершен';
    case 'failed':
      return 'Ошибка';
    case 'canceled':
      return 'Остановлен';
    case 'skipped':
      return 'Пропущен';
    default:
      return status;
  }
}

String relationTypeLabel(String relationType) {
  switch (relationType) {
    case 'manager_to_worker':
      return 'Менеджер -> Воркер';
    case 'dependency':
      return 'Зависимость';
    case 'peer':
      return 'Равный';
    case 'feedback':
      return 'Обратная связь';
    default:
      return relationType;
  }
}

String prettyJson(Object? value) {
  if (value == null) {
    return '';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}
