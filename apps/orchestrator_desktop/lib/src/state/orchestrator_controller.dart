import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/orchestrator_models.dart';
import '../services/orchestrator_api_client.dart';

class OrchestratorController extends ChangeNotifier {
  OrchestratorController({String initialBaseUrl = 'http://127.0.0.1:7081'})
    : _baseUrl = _normalizeBaseUrl(initialBaseUrl),
      _api = OrchestratorApiClient(baseUrl: _normalizeBaseUrl(initialBaseUrl));

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.endsWith('/')) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static const Duration _pollInterval = Duration(seconds: 5);

  String _baseUrl;
  OrchestratorApiClient _api;

  String get baseUrl => _baseUrl;

  OrchestratorHealth? health;
  List<OrchestratorTask> tasks = const [];
  OrchestratorTask? selectedTask;

  bool initializing = false;
  bool reconnecting = false;
  bool loadingHealth = false;
  bool loadingTasks = false;
  bool loadingSelectedTask = false;
  bool creatingTask = false;
  bool cancelingTask = false;
  bool streamConnected = false;
  String? errorMessage;

  Timer? _pollTimer;
  bool _pollInFlight = false;
  StreamSubscription<TaskSseMessage>? _eventsSubscription;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_disposed) {
      return;
    }

    initializing = true;
    errorMessage = null;
    notifyListeners();
    try {
      await refreshHealth(showLoading: false);
      await refreshTasks(showLoading: false, preserveSelection: false);
    } finally {
      if (!_disposed) {
        initializing = false;
        notifyListeners();
      }
    }

    if (_disposed) {
      return;
    }
    _startPolling();
  }

  Future<void> reconnect(String newBaseUrl) async {
    final normalized = _normalizeBaseUrl(newBaseUrl);
    if (normalized.isEmpty) {
      _setError('URL сервера не может быть пустым');
      return;
    }

    reconnecting = true;
    errorMessage = null;
    notifyListeners();

    _stopPolling();
    await _unsubscribeEvents();
    _api.close();

    _baseUrl = normalized;
    _api = OrchestratorApiClient(baseUrl: normalized);
    health = null;
    tasks = const [];
    selectedTask = null;
    streamConnected = false;
    notifyListeners();

    try {
      await initialize();
    } finally {
      reconnecting = false;
      notifyListeners();
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
        if (showLoading) {
          loadingHealth = false;
        }
        notifyListeners();
      }
    }
  }

  Future<void> refreshTasks({
    bool showLoading = true,
    bool preserveSelection = true,
  }) async {
    if (_disposed) {
      return;
    }
    if (showLoading) {
      loadingTasks = true;
      notifyListeners();
    }

    try {
      final loaded = await _api.listTasks(limit: 100);
      loaded.sort(
        (left, right) => (right.createdAt ?? DateTime(1970)).compareTo(
          left.createdAt ?? DateTime(1970),
        ),
      );
      tasks = loaded;
      if (preserveSelection && selectedTask != null) {
        final task = _findTaskById(selectedTask!.id);
        if (task != null) {
          selectedTask = task;
        }
      }
    } catch (error) {
      _setError('Не удалось загрузить /tasks: $error');
    } finally {
      if (!_disposed) {
        if (showLoading) {
          loadingTasks = false;
        }
        notifyListeners();
      }
    }
  }

  Future<void> selectTask(String taskId) async {
    final existing = _findTaskById(taskId);
    if (existing != null) {
      selectedTask = existing;
      errorMessage = null;
      notifyListeners();
    }

    await _loadTask(taskId, showLoading: true);
    await _subscribeToTask(taskId);
  }

  Future<void> createTask(CreateTaskRequest request) async {
    if (_disposed) {
      return;
    }
    creatingTask = true;
    errorMessage = null;
    notifyListeners();

    try {
      final created = await _api.createMinimalTask(request);
      _upsertTask(created);
      selectedTask = created;
      notifyListeners();
      await _loadTask(created.id, showLoading: false);
      await _subscribeToTask(created.id);
    } catch (error) {
      _setError('Не удалось создать задачу: $error');
    } finally {
      if (!_disposed) {
        creatingTask = false;
        notifyListeners();
      }
    }
  }

  Future<void> cancelSelectedTask() async {
    final task = selectedTask;
    if (task == null) {
      return;
    }
    cancelingTask = true;
    errorMessage = null;
    notifyListeners();

    try {
      final updated = await _api.cancelTask(task.id);
      _upsertTask(updated);
      if (selectedTask?.id == updated.id) {
        selectedTask = updated;
      }
    } catch (error) {
      _setError('Не удалось отменить задачу ${task.id}: $error');
    } finally {
      if (!_disposed) {
        cancelingTask = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshSelectedTask() async {
    final task = selectedTask;
    if (task == null) {
      return;
    }
    await _loadTask(task.id, showLoading: true);
  }

  Future<void> _loadTask(String taskId, {required bool showLoading}) async {
    if (_disposed) {
      return;
    }
    if (showLoading) {
      loadingSelectedTask = true;
      notifyListeners();
    }

    try {
      final loaded = await _api.getTask(taskId);
      _upsertTask(loaded);
      if (selectedTask?.id == taskId) {
        selectedTask = loaded;
      }
      errorMessage = null;
    } catch (error) {
      _setError('Не удалось загрузить задачу $taskId: $error');
    } finally {
      if (!_disposed) {
        if (showLoading) {
          loadingSelectedTask = false;
        }
        notifyListeners();
      }
    }
  }

  void _startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_pollInFlight || _disposed) {
        return;
      }
      _pollInFlight = true;
      unawaited(_pollOnce());
    });
  }

  Future<void> _pollOnce() async {
    try {
      await refreshHealth(showLoading: false);
      await refreshTasks(showLoading: false, preserveSelection: true);
      if (selectedTask != null && !isTaskTerminal(selectedTask!.status)) {
        await _loadTask(selectedTask!.id, showLoading: false);
      }
    } finally {
      _pollInFlight = false;
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _subscribeToTask(String taskId) async {
    await _unsubscribeEvents();
    if (_disposed) {
      return;
    }

    streamConnected = false;
    notifyListeners();

    _eventsSubscription = _api
        .streamTaskEvents(taskId)
        .listen(
          (message) {
            if (_disposed) {
              return;
            }
            streamConnected = true;
            _handleSseMessage(message);
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_disposed) {
              return;
            }
            streamConnected = false;
            _setError('Ошибка стрима задач для $taskId: $error');
          },
          onDone: () {
            if (_disposed) {
              return;
            }
            streamConnected = false;
            notifyListeners();
            final current = selectedTask;
            if (current == null ||
                current.id != taskId ||
                isTaskTerminal(current.status)) {
              return;
            }
            Future<void>.delayed(const Duration(seconds: 2), () {
              final stillSelected = selectedTask;
              if (_disposed ||
                  stillSelected == null ||
                  stillSelected.id != taskId ||
                  isTaskTerminal(stillSelected.status)) {
                return;
              }
              unawaited(_subscribeToTask(taskId));
            });
          },
          cancelOnError: true,
        );
  }

  void _handleSseMessage(TaskSseMessage message) {
    if (message.eventName == 'snapshot') {
      final snapshot = OrchestratorTask.fromJson(message.data);
      _upsertTask(snapshot);
      if (selectedTask?.id == snapshot.id) {
        selectedTask = snapshot;
      }
      return;
    }

    if (message.eventName != 'task_event') {
      return;
    }

    final event = TaskStreamEvent.fromJson(message.data);
    final existing = _findTaskById(event.taskId);
    if (existing != null) {
      final timeline = List<TaskTimelineEvent>.from(existing.timeline);
      final alreadyExists = timeline.any(
        (item) => item.sequence == event.event.sequence,
      );
      if (!alreadyExists) {
        timeline.add(event.event);
        timeline.sort((left, right) => left.sequence.compareTo(right.sequence));
      }

      final updated = existing.copyWith(
        status: event.status,
        cancelRequested: event.cancelRequested,
        updatedAt: event.event.at ?? DateTime.now().toUtc(),
        timeline: timeline,
      );
      _upsertTask(updated);
      if (selectedTask?.id == updated.id) {
        selectedTask = updated;
      }
    }

    if (selectedTask?.id == event.taskId && isTaskTerminal(event.status)) {
      unawaited(_loadTask(event.taskId, showLoading: false));
    }
  }

  Future<void> _unsubscribeEvents() async {
    await _eventsSubscription?.cancel();
    _eventsSubscription = null;
    streamConnected = false;
  }

  OrchestratorTask? _findTaskById(String id) {
    for (final task in tasks) {
      if (task.id == id) {
        return task;
      }
    }
    return null;
  }

  void _upsertTask(OrchestratorTask task) {
    final mutable = List<OrchestratorTask>.from(tasks);
    final index = mutable.indexWhere((item) => item.id == task.id);
    if (index >= 0) {
      mutable[index] = task;
    } else {
      mutable.add(task);
    }
    mutable.sort(
      (left, right) => (right.createdAt ?? DateTime(1970)).compareTo(
        left.createdAt ?? DateTime(1970),
      ),
    );
    tasks = mutable;
  }

  void clearError() {
    if (errorMessage == null) {
      return;
    }
    errorMessage = null;
    notifyListeners();
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
    _stopPolling();
    _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _api.close();
    super.dispose();
  }
}
