import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/graph_editor_models.dart';
import '../services/graph_api_client.dart';

class PaletteNodeTemplate {
  const PaletteNodeTemplate({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.nodeType,
    required this.defaultConfig,
  });

  final String key;
  final String title;
  final String subtitle;
  final String nodeType;
  final GraphNodeConfigModel defaultConfig;
}

class GraphEditorController extends ChangeNotifier {
  GraphEditorController({String initialBaseUrl = 'http://127.0.0.1:7081'})
    : _baseUrl = _normalizeBaseUrl(initialBaseUrl),
      _api = GraphApiClient(baseUrl: _normalizeBaseUrl(initialBaseUrl));

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static const double gridSize = 24;
  static const double _defaultNodeWidth = 220;
  static const double _defaultNodeHeight = 140;
  static const String localDraftFileName = 'orchestration_graph_local.json';

  final Random _random = Random();

  String _baseUrl;
  GraphApiClient _api;

  String get baseUrl => _baseUrl;

  bool initializing = false;
  bool reconnecting = false;
  bool loadingHealth = false;
  bool loadingGraphs = false;
  bool loadingRuns = false;
  bool savingGraph = false;
  bool runningGraph = false;
  bool stoppingRun = false;
  bool loadingNodeDialog = false;
  bool sendingNodeMessage = false;
  bool runStreamConnected = false;

  String? errorMessage;
  String? infoMessage;

  Map<String, dynamic>? health;

  String graphName = 'Новая схема оркестрации';
  String graphDescription = '';
  String projectFilesPath = '';
  String? activeGraphId;
  int graphRevision = 1;

  List<GraphNodeModel> nodes = const [];
  List<GraphEdgeModel> edges = const [];

  final Set<String> selectedNodeIds = <String>{};
  String? selectedEdgeId;
  String selectedRelationType = 'manager_to_worker';

  bool snapToGrid = true;

  List<OrchestrationGraphModel> availableGraphs = const [];
  List<GraphRunModel> availableRuns = const [];
  GraphRunModel? activeRun;

  final Map<String, List<NodeChatMessageModel>> nodeMessages =
      <String, List<NodeChatMessageModel>>{};
  final Map<String, List<NodeLogEntryModel>> nodeLogs =
      <String, List<NodeLogEntryModel>>{};

  StreamSubscription<GraphSseMessage>? _runEventsSubscription;
  bool _disposed = false;

  List<PaletteNodeTemplate> get palette {
    return const [
      PaletteNodeTemplate(
        key: 'codex-manager',
        title: 'Менеджер Codex',
        subtitle: 'Координатор / планировщик',
        nodeType: 'manager',
        defaultConfig: GraphNodeConfigModel(
          agentId: 'codex',
          role: 'manager',
          timeoutMs: 90000,
          maxRetries: 0,
          retryDelayMs: 1000,
        ),
      ),
      PaletteNodeTemplate(
        key: 'qwen-worker',
        title: 'Воркер Qwen',
        subtitle: 'Исполнитель задач',
        nodeType: 'worker',
        defaultConfig: GraphNodeConfigModel(
          agentId: 'qwen',
          role: 'worker',
          timeoutMs: 120000,
          maxRetries: 1,
          retryDelayMs: 1500,
        ),
      ),
      PaletteNodeTemplate(
        key: 'generic-agent',
        title: 'Универсальный агент',
        subtitle: 'Будущая роль / модель',
        nodeType: 'agent',
        defaultConfig: GraphNodeConfigModel(
          agentId: 'qwen',
          role: 'worker',
          timeoutMs: 120000,
          maxRetries: 0,
          retryDelayMs: 1000,
        ),
      ),
    ];
  }

  Future<void> initialize() async {
    if (_disposed) {
      return;
    }

    initializing = true;
    errorMessage = null;
    notifyListeners();

    try {
      await refreshHealth(showLoading: false);
      await refreshGraphs(showLoading: false);

      if (availableGraphs.isNotEmpty) {
        await loadGraph(availableGraphs.first.id);
      } else {
        _setDefaultGraph();
      }
    } catch (error) {
      _setError('Ошибка инициализации: $error');
      _setDefaultGraph();
    } finally {
      if (!_disposed) {
        initializing = false;
        notifyListeners();
      }
    }
  }

  Future<void> reconnect(String nextBaseUrl) async {
    final normalized = _normalizeBaseUrl(nextBaseUrl);
    if (normalized.isEmpty) {
      _setError('URL сервера не может быть пустым');
      return;
    }

    reconnecting = true;
    errorMessage = null;
    notifyListeners();

    await _runEventsSubscription?.cancel();
    _runEventsSubscription = null;

    final previousBaseUrl = _baseUrl;
    final previousApi = _api;
    final nextApi = GraphApiClient(baseUrl: normalized);

    try {
      final nextHealth = await nextApi.getHealth();
      final nextGraphs = await nextApi.listGraphs(limit: 100);

      _baseUrl = normalized;
      _api = nextApi;
      previousApi.close();

      health = nextHealth;
      availableGraphs = nextGraphs;
      availableRuns = const [];
      activeRun = null;
      runStreamConnected = false;
      nodeMessages.clear();
      nodeLogs.clear();

      if (availableGraphs.isNotEmpty) {
        await loadGraph(availableGraphs.first.id);
        clearInfo();
      } else {
        // Keep canvas as local draft when backend has no saved graphs yet.
        activeGraphId = null;
        graphRevision = 1;
        infoMessage =
            'Connected to $normalized. Backend has no saved graphs yet.';
        notifyListeners();
      }
    } catch (error) {
      nextApi.close();
      _baseUrl = previousBaseUrl;
      _api = previousApi;
      _setError('Failed to connect to $normalized: $error');
    } finally {
      if (!_disposed) {
        reconnecting = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshHealth({bool showLoading = true}) async {
    if (_disposed) {
      return;
    }

    if (showLoading) {
      loadingHealth = true;
      notifyListeners();
    }

    try {
      health = await _api.getHealth();
    } catch (error) {
      _setError('Не удалось загрузить /health: $error');
    } finally {
      if (!_disposed) {
        loadingHealth = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshGraphs({bool showLoading = true}) async {
    if (_disposed) {
      return;
    }

    if (showLoading) {
      loadingGraphs = true;
      notifyListeners();
    }

    try {
      final items = await _api.listGraphs(limit: 100);
      availableGraphs = items;
    } catch (error) {
      _setError('Не удалось загрузить схемы: $error');
    } finally {
      if (!_disposed) {
        loadingGraphs = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshRuns({bool showLoading = true}) async {
    if (_disposed || activeGraphId == null) {
      return;
    }

    if (showLoading) {
      loadingRuns = true;
      notifyListeners();
    }

    try {
      final runs = await _api.listGraphRuns(activeGraphId!, limit: 50);
      availableRuns = runs;

      final current = activeRun;
      if (current != null) {
        final replacement = runs
            .where((item) => item.runId == current.runId)
            .firstOrNull;
        if (replacement != null) {
          activeRun = replacement;
          if (!isGraphRunTerminal(replacement.status)) {
            await _subscribeToRun(replacement.runId);
          }
        }
      }
    } catch (error) {
      _setError('Не удалось загрузить запуски схемы: $error');
    } finally {
      if (!_disposed) {
        loadingRuns = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadGraph(String graphId) async {
    if (_disposed) {
      return;
    }

    try {
      final graph = await _api.getGraph(graphId);
      _applyGraph(graph);
      await refreshRuns(showLoading: false);
      clearInfo();
    } catch (error) {
      _setError('Не удалось загрузить схему $graphId: $error');
    }
  }

  void _applyGraph(OrchestrationGraphModel graph) {
    activeGraphId = graph.id;
    graphName = graph.name;
    graphDescription = graph.description ?? '';
    graphRevision = graph.revision.revision;
    nodes = graph.revision.nodes;
    edges = graph.revision.edges;
    _syncProjectPathFromNodesIfUniform();
    selectedNodeIds.clear();
    selectedEdgeId = null;
    activeRun = null;
    availableRuns = const [];
    nodeMessages.clear();
    nodeLogs.clear();
    runStreamConnected = false;
    notifyListeners();
  }

  void setGraphName(String value) {
    graphName = value;
    notifyListeners();
  }

  void setGraphDescription(String value) {
    graphDescription = value;
    notifyListeners();
  }

  void setProjectFilesPath(String value) {
    projectFilesPath = value.trim();
    notifyListeners();
  }

  void setSelectedRelationType(String relationType) {
    selectedRelationType = relationType;
    notifyListeners();
  }

  void toggleSnapToGrid(bool enabled) {
    snapToGrid = enabled;
    notifyListeners();
  }

  void addNodeFromTemplate(PaletteNodeTemplate template, double x, double y) {
    final snapped = _snapPoint(x, y);
    final free = _findNonOverlappingNodePosition(snapped.dx, snapped.dy);
    final node = GraphNodeModel(
      id: _newId('node'),
      type: template.nodeType,
      label: _dedupeNodeLabel(template.title),
      x: free.dx,
      y: free.dy,
      config: template.defaultConfig,
    );

    nodes = [...nodes, node];
    selectedNodeIds
      ..clear()
      ..add(node.id);
    selectedEdgeId = null;
    _bumpLocalRevision();
  }

  void addNodeFromTemplateAuto(PaletteNodeTemplate template) {
    if (nodes.isEmpty) {
      addNodeFromTemplate(template, 220, 180);
      return;
    }

    final last = nodes.last;
    final offsetX = _defaultNodeWidth + (gridSize * 2);
    final offsetY = gridSize * 2;
    addNodeFromTemplate(template, last.x + offsetX, last.y + offsetY);
  }

  void selectNode(String nodeId, {bool additive = false, bool toggle = false}) {
    selectedEdgeId = null;

    if (toggle) {
      if (selectedNodeIds.contains(nodeId)) {
        selectedNodeIds.remove(nodeId);
      } else {
        selectedNodeIds.add(nodeId);
      }
      notifyListeners();
      return;
    }

    if (additive) {
      selectedNodeIds.add(nodeId);
      notifyListeners();
      return;
    }

    selectedNodeIds
      ..clear()
      ..add(nodeId);
    notifyListeners();
  }

  void selectEdge(String edgeId) {
    selectedNodeIds.clear();
    selectedEdgeId = edgeId;
    notifyListeners();
  }

  void clearSelection() {
    if (selectedNodeIds.isEmpty && selectedEdgeId == null) {
      return;
    }
    selectedNodeIds.clear();
    selectedEdgeId = null;
    notifyListeners();
  }

  void selectAllNodes() {
    selectedNodeIds
      ..clear()
      ..addAll(nodes.map((node) => node.id));
    selectedEdgeId = null;
    notifyListeners();
  }

  void moveSelectedNodes(double deltaX, double deltaY) {
    if (selectedNodeIds.isEmpty) {
      return;
    }

    final updated = nodes
        .map((node) {
          if (!selectedNodeIds.contains(node.id)) {
            return node;
          }
          final nextX = node.x + deltaX;
          final nextY = node.y + deltaY;
          final snapped = _snapPoint(nextX, nextY);
          return node.copyWith(x: snapped.dx, y: snapped.dy);
        })
        .toList(growable: false);

    nodes = updated;
    _bumpLocalRevision();
  }

  void moveNode(String nodeId, double nextX, double nextY) {
    final snapped = _snapPoint(nextX, nextY);
    nodes = nodes
        .map((node) {
          if (node.id != nodeId) {
            return node;
          }
          return node.copyWith(x: snapped.dx, y: snapped.dy);
        })
        .toList(growable: false);
    _bumpLocalRevision();
  }

  void updateNode(
    String nodeId, {
    String? label,
    String? type,
    String? agentId,
    String? role,
    bool? fullAccess,
    String? cwd,
    bool clearCwd = false,
    String? prompt,
    bool clearPrompt = false,
    int? timeoutMs,
    bool clearTimeoutMs = false,
    int? maxRetries,
    bool clearMaxRetries = false,
    int? retryDelayMs,
    bool clearRetryDelayMs = false,
  }) {
    nodes = nodes
        .map((node) {
          if (node.id != nodeId) {
            return node;
          }

          final nextConfig = node.config.copyWith(
            agentId: agentId,
            role: role,
            fullAccess: fullAccess,
            cwd: cwd,
            clearCwd: clearCwd,
            prompt: prompt,
            clearPrompt: clearPrompt,
            timeoutMs: timeoutMs,
            clearTimeoutMs: clearTimeoutMs,
            maxRetries: maxRetries,
            clearMaxRetries: clearMaxRetries,
            retryDelayMs: retryDelayMs,
            clearRetryDelayMs: clearRetryDelayMs,
          );

          return node.copyWith(label: label, type: type, config: nextConfig);
        })
        .toList(growable: false);

    _bumpLocalRevision();
  }

  void deleteSelection() {
    if (selectedEdgeId != null) {
      deleteEdge(selectedEdgeId!);
      return;
    }

    if (selectedNodeIds.isEmpty) {
      return;
    }

    final removed = Set<String>.from(selectedNodeIds);
    nodes = nodes
        .where((node) => !removed.contains(node.id))
        .toList(growable: false);
    edges = edges
        .where(
          (edge) =>
              !removed.contains(edge.fromNodeId) &&
              !removed.contains(edge.toNodeId),
        )
        .toList(growable: false);

    selectedNodeIds.clear();
    selectedEdgeId = null;
    _bumpLocalRevision();
  }

  bool createEdge(String fromNodeId, String toNodeId, {String? relationType}) {
    if (fromNodeId == toNodeId) {
      _setError('Связь не может соединять узел с самим собой');
      return false;
    }

    final fromExists = nodes.any((node) => node.id == fromNodeId);
    final toExists = nodes.any((node) => node.id == toNodeId);
    if (!fromExists || !toExists) {
      _setError('Связь ссылается на отсутствующий узел');
      return false;
    }

    final existing = edges
        .where(
          (edge) => edge.fromNodeId == fromNodeId && edge.toNodeId == toNodeId,
        )
        .firstOrNull;
    if (existing != null) {
      selectedNodeIds.clear();
      selectedEdgeId = existing.id;
      infoMessage = 'Связь уже существует. Выбрана существующая связь.';
      notifyListeners();
      return false;
    }

    final edge = GraphEdgeModel(
      id: _newId('edge'),
      fromNodeId: fromNodeId,
      toNodeId: toNodeId,
      relationType: relationType ?? selectedRelationType,
    );

    edges = [...edges, edge];
    selectedNodeIds.clear();
    selectedEdgeId = edge.id;
    _bumpLocalRevision();
    return true;
  }

  void updateSelectedEdgeRelation(String relationType) {
    final edgeId = selectedEdgeId;
    if (edgeId == null) {
      return;
    }

    edges = edges
        .map((edge) {
          if (edge.id != edgeId) {
            return edge;
          }
          return edge.copyWith(relationType: relationType);
        })
        .toList(growable: false);

    _bumpLocalRevision();
  }

  void deleteEdge(String edgeId) {
    edges = edges.where((edge) => edge.id != edgeId).toList(growable: false);
    if (selectedEdgeId == edgeId) {
      selectedEdgeId = null;
    }
    _bumpLocalRevision();
  }

  Future<bool> saveGraphToBackend() async {
    if (_disposed) {
      return false;
    }

    final trimmedName = graphName.trim();
    if (trimmedName.isEmpty) {
      _setError('Graph name cannot be empty');
      return false;
    }

    if (nodes.isEmpty) {
      _setError('Add at least one node before saving');
      return false;
    }

    savingGraph = true;
    errorMessage = null;
    notifyListeners();

    try {
      _applyProjectPathToNodesWithoutCwd();
      final request = GraphUpsertRequest(
        name: trimmedName,
        description: graphDescription.trim().isEmpty
            ? null
            : graphDescription.trim(),
        nodes: nodes,
        edges: edges,
      );

      OrchestrationGraphModel saved;
      if (activeGraphId == null) {
        saved = await _api.createGraph(request);
      } else {
        try {
          saved = await _api.updateGraph(activeGraphId!, request);
        } on ApiException catch (error) {
          if (error.statusCode == 404) {
            // Local draft can contain stale graphId that no longer exists on backend.
            activeGraphId = null;
            saved = await _api.createGraph(request);
          } else {
            rethrow;
          }
        }
      }

      _applyGraph(saved);
      await refreshGraphs(showLoading: false);
      await refreshRuns(showLoading: false);
      infoMessage = 'Graph saved (revision ${saved.revision.revision}).';
      return true;
    } catch (error) {
      _setError('Failed to save graph: $error');
      return false;
    } finally {
      if (!_disposed) {
        savingGraph = false;
        notifyListeners();
      }
    }
  }

  Future<GraphValidationResultModel?> validateGraph() async {
    if (_disposed) {
      return null;
    }

    final saved = await saveGraphToBackend();
    if (!saved || _disposed || activeGraphId == null) {
      return null;
    }

    try {
      final result = await _api.validateGraph(
        activeGraphId!,
        graphRevision: graphRevision,
      );
      infoMessage = result.valid
          ? 'Схема валидна. Топологический порядок: ${result.topologicalOrder.join(', ')}'
          : 'Проверка схемы не пройдена: ${result.errors.join('; ')}';
      notifyListeners();
      return result;
    } catch (error) {
      _setError('Не удалось проверить схему: $error');
      return null;
    }
  }

  Future<bool> startRun({
    String? kickoffMessage,
    String? kickoffManagerNodeId,
  }) async {
    if (_disposed) {
      return false;
    }

    if (runningGraph) {
      _setError('Run is already starting. Please wait.');
      return false;
    }

    runningGraph = true;
    errorMessage = null;
    notifyListeners();

    try {
      final saved = await saveGraphToBackend();
      if (!saved || activeGraphId == null) {
        return false;
      }

      final run = await _api.createGraphRun(
        activeGraphId!,
        graphRevision: graphRevision,
        kickoffMessage: kickoffMessage,
        kickoffManagerNodeId: kickoffManagerNodeId,
      );
      _upsertRun(run);
      activeRun = run;
      await _subscribeToRun(run.runId);
      infoMessage =
          kickoffMessage != null && kickoffMessage.trim().isNotEmpty
          ? 'Run started from manager task: ${run.runId}'
          : 'Run started: ${run.runId}';
      return true;
    } catch (error) {
      _setError('Failed to start graph run: $error');
      return false;
    } finally {
      if (!_disposed) {
        runningGraph = false;
        notifyListeners();
      }
    }
  }

  Future<void> stopRun() async {
    final run = activeRun;
    if (_disposed || run == null || stoppingRun) {
      return;
    }

    if (isGraphRunTerminal(run.status)) {
      return;
    }

    stoppingRun = true;
    errorMessage = null;
    notifyListeners();

    try {
      final canceled = await _api.cancelGraphRun(run.runId);
      _upsertRun(canceled);
      activeRun = canceled;
      infoMessage = 'Запрошена остановка запуска ${run.runId}';
    } catch (error) {
      _setError('Не удалось остановить запуск ${run.runId}: $error');
    } finally {
      if (!_disposed) {
        stoppingRun = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectRun(String runId) async {
    if (_disposed) {
      return;
    }

    try {
      final run = await _api.getGraphRun(runId);
      activeRun = run;
      _upsertRun(run);
      await _subscribeToRun(runId);
      notifyListeners();
    } catch (error) {
      _setError('Не удалось загрузить запуск $runId: $error');
    }
  }

  Future<void> _subscribeToRun(String runId) async {
    await _runEventsSubscription?.cancel();
    _runEventsSubscription = null;

    if (_disposed) {
      return;
    }

    runStreamConnected = false;
    notifyListeners();

    _runEventsSubscription = _api
        .streamRunEvents(runId)
        .listen(
          (message) {
            if (_disposed) {
              return;
            }

            runStreamConnected = true;
            _applyRunSseMessage(message);
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed) {
              return;
            }
            runStreamConnected = false;
            _setError('Ошибка SSE для запуска $runId: $error');
          },
          onDone: () {
            if (_disposed) {
              return;
            }
            runStreamConnected = false;
            notifyListeners();
          },
          cancelOnError: true,
        );
  }

  void _applyRunSseMessage(GraphSseMessage message) {
    if (message.eventName == 'snapshot') {
      final snapshot = GraphRunModel.fromJson(message.data);
      activeRun = snapshot;
      _upsertRun(snapshot);
      return;
    }

    if (message.eventName != 'run_event' || activeRun == null) {
      return;
    }

    final streamed = GraphRunStreamEventModel.fromJson(message.data);
    if (activeRun!.runId != streamed.runId) {
      return;
    }

    final current = activeRun!;
    final nextEvents = List<GraphRunEventModel>.from(current.events);
    if (!nextEvents.any((event) => event.sequence == streamed.event.sequence)) {
      nextEvents.add(streamed.event);
      nextEvents.sort((a, b) => a.sequence.compareTo(b.sequence));
    }

    var nextNodeStates = Map<String, GraphRunNodeStateModel>.from(
      current.nodeStates,
    );

    final data = streamed.event.data ?? const <String, dynamic>{};
    final eventNodeId = _readString(data['nodeId']) ?? streamed.event.nodeId;

    if (streamed.event.type == 'node_status_changed' && eventNodeId != null) {
      final previous =
          nextNodeStates[eventNodeId] ??
          GraphRunNodeStateModel(
            nodeId: eventNodeId,
            status: 'pending',
            attempts: 0,
          );

      final status = _readString(data['status']) ?? previous.status;
      final attempts = _readInt(data['attempts']) ?? previous.attempts;
      final lastError = _readString(data['lastError']);
      final lastPrompt = _readString(data['lastPrompt']);

      nextNodeStates[eventNodeId] = previous.copyWith(
        status: status,
        attempts: attempts,
        lastError: lastError,
        clearLastError: lastError == null,
        lastPrompt: lastPrompt,
        clearLastPrompt: lastPrompt == null,
      );
    }

    if (streamed.event.type == 'node_log_chunk' && eventNodeId != null) {
      final sequence = _readInt(data['sequence']) ?? 0;
      final stream = _readString(data['stream']) ?? 'system';
      final chunk = _readString(data['chunk']) ?? '';

      final existing = List<NodeLogEntryModel>.from(
        nodeLogs[eventNodeId] ?? const [],
      );
      if (!existing.any(
        (entry) => entry.sequence == sequence && entry.runId == streamed.runId,
      )) {
        existing.add(
          NodeLogEntryModel(
            id: '${streamed.runId}-$eventNodeId-$sequence',
            graphId: streamed.event.graphId,
            nodeId: eventNodeId,
            runId: streamed.runId,
            stream: stream,
            chunk: chunk,
            sequence: sequence,
            createdAt: streamed.event.at,
          ),
        );
      }
      existing.sort((a, b) => a.sequence.compareTo(b.sequence));
      nodeLogs[eventNodeId] = existing;
    }

    final updated = current.copyWith(
      status: streamed.status,
      cancelRequested: streamed.cancelRequested,
      updatedAt: streamed.event.at,
      nodeStates: nextNodeStates,
      events: nextEvents,
    );

    activeRun = updated;
    _upsertRun(updated);

    if (streamed.event.type == 'node_result_ready' ||
        streamed.event.type == 'graph_run_finished') {
      unawaited(_refreshActiveRun());
    }
  }

  Future<void> _refreshActiveRun() async {
    final runId = activeRun?.runId;
    if (runId == null || _disposed) {
      return;
    }

    try {
      final run = await _api.getGraphRun(runId);
      activeRun = run;
      _upsertRun(run);
      notifyListeners();
    } catch (error) {
      _setError('Не удалось обновить запуск $runId: $error');
    }
  }

  Future<void> loadNodeDialogData(String nodeId) async {
    if (_disposed || activeGraphId == null) {
      return;
    }

    loadingNodeDialog = true;
    errorMessage = null;
    notifyListeners();

    try {
      final runId = activeRun?.runId;
      final responses = await Future.wait([
        _api.listNodeMessages(nodeId, graphId: activeGraphId, limit: 200),
        _api.listNodeLogs(
          nodeId,
          graphId: activeGraphId,
          runId: runId,
          limit: 500,
        ),
      ]);

      nodeMessages[nodeId] = responses[0] as List<NodeChatMessageModel>;
      nodeLogs[nodeId] = responses[1] as List<NodeLogEntryModel>;
    } catch (error) {
      _setError('Не удалось загрузить данные диалога узла: $error');
    } finally {
      if (!_disposed) {
        loadingNodeDialog = false;
        notifyListeners();
      }
    }
  }

  Future<bool> sendMessageToNode(String nodeId, String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || _disposed) {
      return false;
    }

    sendingNodeMessage = true;
    errorMessage = null;
    notifyListeners();

    try {
      final node = nodes.where((item) => item.id == nodeId).firstOrNull;
      final isManagerNode =
          node != null &&
          (node.type == 'manager' || node.config.role == 'manager');

      if (isManagerNode) {
        final started = await startRun(
          kickoffMessage: trimmed,
          kickoffManagerNodeId: nodeId,
        );
        if (!started) {
          return false;
        }
        await loadNodeDialogData(nodeId);
        return true;
      }

      if (activeGraphId == null) {
        _setError('Save graph before sending messages to non-manager nodes.');
        return false;
      }

      final response = await _api.sendNodeMessage(
        nodeId,
        NodeChatRequestModel(
          message: trimmed,
          graphId: activeGraphId,
          runId: activeRun?.runId,
          cwd: node?.config.cwd?.trim().isNotEmpty == true
              ? node!.config.cwd
              : projectFilesPath.trim().isEmpty
              ? null
              : projectFilesPath.trim(),
        ),
      );

      final existing = List<NodeChatMessageModel>.from(
        nodeMessages[nodeId] ?? const [],
      );
      existing.add(response.userMessage);
      existing.add(response.assistantMessage);
      existing.sort(
        (left, right) => (left.createdAt ?? DateTime(1970)).compareTo(
          right.createdAt ?? DateTime(1970),
        ),
      );
      nodeMessages[nodeId] = existing;

      await loadNodeDialogData(nodeId);
      return true;
    } catch (error) {
      _setError('Failed to send node message: $error');
      return false;
    } finally {
      if (!_disposed) {
        sendingNodeMessage = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveLocalDraft() async {
    final payload = {
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'baseUrl': baseUrl,
      'projectFilesPath': projectFilesPath,
      'graph': {
        'graphId': activeGraphId,
        'name': graphName,
        'description': graphDescription,
        'revision': graphRevision,
        'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
        'edges': edges.map((edge) => edge.toJson()).toList(growable: false),
      },
    };

    try {
      final file = File(_localDraftPath());
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      infoMessage = 'Локальный черновик сохранен: ${file.path}';
      notifyListeners();
    } catch (error) {
      _setError('Не удалось сохранить локальный черновик: $error');
    }
  }

  Future<void> loadLocalDraft() async {
    try {
      final file = File(_localDraftPath());
      if (!await file.exists()) {
        _setError('Локальный черновик не найден: ${file.path}');
        return;
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _setError('Некорректный формат локального черновика');
        return;
      }

      final graphRaw = decoded['graph'];
      if (graphRaw is! Map) {
        _setError('Некорректные данные локального черновика');
        return;
      }

      final graphMap = graphRaw.map((key, value) => MapEntry('$key', value));
      projectFilesPath = _readString(decoded['projectFilesPath']) ?? '';

      graphName = _readString(graphMap['name']) ?? graphName;
      graphDescription = _readString(graphMap['description']) ?? '';
      graphRevision = 1;
      activeGraphId = null;

      final loadedNodes = <GraphNodeModel>[];
      final nodeList = graphMap['nodes'];
      if (nodeList is List) {
        for (final item in nodeList) {
          if (item is Map) {
            loadedNodes.add(
              GraphNodeModel.fromJson(
                item.map((key, value) => MapEntry('$key', value)),
              ),
            );
          }
        }
      }

      final loadedEdges = <GraphEdgeModel>[];
      final edgeList = graphMap['edges'];
      if (edgeList is List) {
        for (final item in edgeList) {
          if (item is Map) {
            loadedEdges.add(
              GraphEdgeModel.fromJson(
                item.map((key, value) => MapEntry('$key', value)),
              ),
            );
          }
        }
      }

      nodes = loadedNodes;
      edges = loadedEdges;
      if (projectFilesPath.trim().isEmpty) {
        _syncProjectPathFromNodesIfUniform();
      }
      selectedNodeIds.clear();
      selectedEdgeId = null;
      activeRun = null;
      availableRuns = const [];
      runStreamConnected = false;
      nodeLogs.clear();
      nodeMessages.clear();

      infoMessage = 'Локальный черновик загружен: ${file.path}';
      notifyListeners();
    } catch (error) {
      _setError('Не удалось загрузить локальный черновик: $error');
    }
  }

  String _localDraftPath() {
    return '${Directory.current.path}${Platform.pathSeparator}$localDraftFileName';
  }

  GraphNodeModel? get selectedSingleNode {
    if (selectedNodeIds.length != 1) {
      return null;
    }
    final nodeId = selectedNodeIds.first;
    return nodes.where((node) => node.id == nodeId).firstOrNull;
  }

  GraphEdgeModel? get selectedEdge {
    final edgeId = selectedEdgeId;
    if (edgeId == null) {
      return null;
    }
    return edges.where((edge) => edge.id == edgeId).firstOrNull;
  }

  String nodeStatus(String nodeId) {
    return activeRun?.nodeStates[nodeId]?.status ?? 'pending';
  }

  String? nodeError(String nodeId) {
    return activeRun?.nodeStates[nodeId]?.lastError;
  }

  void clearError() {
    if (errorMessage == null) {
      return;
    }
    errorMessage = null;
    notifyListeners();
  }

  void clearInfo() {
    if (infoMessage == null) {
      return;
    }
    infoMessage = null;
    notifyListeners();
  }

  void _setDefaultGraph() {
    graphName = 'Новая схема оркестрации';
    graphDescription = '';
    projectFilesPath = '';
    activeGraphId = null;
    graphRevision = 1;
    nodes = const [];
    edges = const [];
    selectedNodeIds.clear();
    selectedEdgeId = null;
    activeRun = null;
    availableRuns = const [];
    nodeMessages.clear();
    nodeLogs.clear();
    runStreamConnected = false;
  }

  void _upsertRun(GraphRunModel run) {
    final mutable = List<GraphRunModel>.from(availableRuns);
    final index = mutable.indexWhere((item) => item.runId == run.runId);
    if (index >= 0) {
      mutable[index] = run;
    } else {
      mutable.add(run);
    }
    mutable.sort(
      (left, right) => (right.createdAt ?? DateTime(1970)).compareTo(
        left.createdAt ?? DateTime(1970),
      ),
    );
    availableRuns = mutable;
  }

  String _newId(String prefix) {
    final randomPart = _random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$randomPart';
  }

  String _dedupeNodeLabel(String base) {
    final labels = nodes.map((node) => node.label).toSet();
    if (!labels.contains(base)) {
      return base;
    }

    var index = 2;
    while (labels.contains('$base $index')) {
      index += 1;
    }
    return '$base $index';
  }

  ({double dx, double dy}) _snapPoint(double x, double y) {
    if (!snapToGrid) {
      return (dx: x, dy: y);
    }

    final snappedX = (x / gridSize).round() * gridSize;
    final snappedY = (y / gridSize).round() * gridSize;
    return (dx: snappedX, dy: snappedY);
  }

  ({double dx, double dy}) _findNonOverlappingNodePosition(double x, double y) {
    var candidate = (dx: x, dy: y);
    const maxAttempts = 120;
    final shift = gridSize * 2;

    var attempt = 0;
    while (_hasNodeOverlapAt(candidate.dx, candidate.dy) &&
        attempt < maxAttempts) {
      candidate = _snapPoint(candidate.dx + shift, candidate.dy + shift);
      attempt += 1;
    }

    return candidate;
  }

  bool _hasNodeOverlapAt(double x, double y) {
    final left = x;
    final top = y;
    final right = x + _defaultNodeWidth;
    final bottom = y + _defaultNodeHeight;

    for (final node in nodes) {
      final nodeLeft = node.x;
      final nodeTop = node.y;
      final nodeRight = node.x + _defaultNodeWidth;
      final nodeBottom = node.y + _defaultNodeHeight;

      final intersects =
          left < nodeRight &&
          right > nodeLeft &&
          top < nodeBottom &&
          bottom > nodeTop;
      if (intersects) {
        return true;
      }
    }
    return false;
  }

  void _applyProjectPathToNodesWithoutCwd() {
    final projectPath = projectFilesPath.trim();
    if (projectPath.isEmpty) {
      return;
    }

    var changed = false;
    final updated = nodes
        .map((node) {
          final nodeCwd = node.config.cwd?.trim();
          if (nodeCwd != null && nodeCwd.isNotEmpty) {
            return node;
          }

          changed = true;
          return node.copyWith(config: node.config.copyWith(cwd: projectPath));
        })
        .toList(growable: false);

    if (changed) {
      nodes = updated;
      _bumpLocalRevision();
    }
  }

  void _syncProjectPathFromNodesIfUniform() {
    if (nodes.isEmpty) {
      projectFilesPath = '';
      return;
    }

    final values = nodes
        .map((node) => node.config.cwd?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

    if (values.isEmpty) {
      projectFilesPath = '';
      return;
    }

    final first = values.first;
    final uniform = values.every((value) => value == first) &&
        nodes.every((node) => (node.config.cwd?.trim() ?? '').isNotEmpty);

    projectFilesPath = uniform ? first : '';
  }

  void _bumpLocalRevision() {
    // Backend owns canonical revision numbers. For a local unsaved graph we
    // keep a stable placeholder revision to avoid growing on every drag event.
    if (activeGraphId == null) {
      graphRevision = 1;
    }
    infoMessage = null;
    notifyListeners();
  }

  String? _readString(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  void _setError(String message) {
    if (_disposed) {
      return;
    }
    errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _runEventsSubscription?.cancel();
    _runEventsSubscription = null;
    _api.close();
    super.dispose();
  }
}

extension _IterableNullable<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
