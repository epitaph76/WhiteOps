// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/graph_editor_models.dart';
import '../state/graph_editor_controller.dart';
import 'graph_canvas_view.dart';
import 'graph_ui_models.dart';
import 'node_dialog_modal.dart';

class GraphEditorPage extends StatefulWidget {
  const GraphEditorPage({super.key});

  @override
  State<GraphEditorPage> createState() => _GraphEditorPageState();
}

class _GraphEditorPageState extends State<GraphEditorPage> {
  late final GraphEditorController _controller;
  late final TextEditingController _serverController;
  late final TextEditingController _graphNameController;
  late final TextEditingController _graphDescriptionController;
  late final TextEditingController _projectFilesPathController;
  final FocusNode _shortcutsFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = GraphEditorController();
    _serverController = TextEditingController(text: _controller.baseUrl);
    _graphNameController = TextEditingController(text: _controller.graphName);
    _graphDescriptionController = TextEditingController(
      text: _controller.graphDescription,
    );
    _projectFilesPathController = TextEditingController(
      text: _controller.projectFilesPath,
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    _serverController.dispose();
    _graphNameController.dispose();
    _graphDescriptionController.dispose();
    _projectFilesPathController.dispose();
    _shortcutsFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        _syncFormControllers();
        return Shortcuts(
          shortcuts: _buildShortcuts(),
          child: Actions(
            actions: _buildActions(),
            child: Focus(
              autofocus: true,
              focusNode: _shortcutsFocusNode,
              child: Scaffold(
                body: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFF5FAFC), Color(0xFFE8EEF3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildHeader(),
                          if (_controller.errorMessage != null) ...[
                            const SizedBox(height: 10),
                            _buildErrorBanner(_controller.errorMessage!),
                          ],
                          if (_controller.infoMessage != null) ...[
                            const SizedBox(height: 10),
                            _buildInfoBanner(_controller.infoMessage!),
                          ],
                          const SizedBox(height: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 1280;
                                if (narrow) {
                                  return Column(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: GraphCanvasView(
                                          controller: _controller,
                                          onNodeDoubleTap: (node) =>
                                              unawaited(_openNodeDialog(node)),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: constraints.maxHeight * 0.42,
                                        child: _buildSidebar(),
                                      ),
                                    ],
                                  );
                                }

                                return Row(
                                  children: [
                                    Expanded(
                                      flex: 7,
                                      child: GraphCanvasView(
                                        controller: _controller,
                                        onNodeDoubleTap: (node) =>
                                            unawaited(_openNodeDialog(node)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 380,
                                      child: _buildSidebar(),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Map<ShortcutActivator, Intent> _buildShortcuts() {
    return <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.delete): const DeleteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true):
          const SelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
          const SelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.escape):
          const ClearSelectionIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          const SaveGraphIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
          const SaveGraphIntent(),
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ): const SaveLocalIntent(),
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true):
          const SaveLocalIntent(),
      const SingleActivator(LogicalKeyboardKey.keyL, control: true):
          const LoadLocalIntent(),
      const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
          const LoadLocalIntent(),
    };
  }

  Map<Type, Action<Intent>> _buildActions() {
    return <Type, Action<Intent>>{
      DeleteIntent: CallbackAction<DeleteIntent>(
        onInvoke: (_) {
          if (_isTextInputFocused()) {
            return null;
          }
          _controller.deleteSelection();
          return null;
        },
      ),
      SelectAllIntent: CallbackAction<SelectAllIntent>(
        onInvoke: (_) {
          _controller.selectAllNodes();
          return null;
        },
      ),
      ClearSelectionIntent: CallbackAction<ClearSelectionIntent>(
        onInvoke: (_) {
          _controller.clearSelection();
          return null;
        },
      ),
      SaveGraphIntent: CallbackAction<SaveGraphIntent>(
        onInvoke: (_) {
          unawaited(_controller.saveGraphToBackend());
          return null;
        },
      ),
      SaveLocalIntent: CallbackAction<SaveLocalIntent>(
        onInvoke: (_) {
          unawaited(_controller.saveLocalDraft());
          return null;
        },
      ),
      LoadLocalIntent: CallbackAction<LoadLocalIntent>(
        onInvoke: (_) {
          unawaited(_controller.loadLocalDraft());
          return null;
        },
      ),
    };
  }

  bool _isTextInputFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final focusedWidget = focusedContext?.widget;
    return focusedWidget is EditableText;
  }

  void _syncFormControllers() {
    if (_graphNameController.text != _controller.graphName) {
      _graphNameController.text = _controller.graphName;
      _graphNameController.selection = TextSelection.fromPosition(
        TextPosition(offset: _graphNameController.text.length),
      );
    }

    if (_graphDescriptionController.text != _controller.graphDescription) {
      _graphDescriptionController.text = _controller.graphDescription;
      _graphDescriptionController.selection = TextSelection.fromPosition(
        TextPosition(offset: _graphDescriptionController.text.length),
      );
    }

    if (_serverController.text != _controller.baseUrl) {
      _serverController.text = _controller.baseUrl;
      _serverController.selection = TextSelection.fromPosition(
        TextPosition(offset: _serverController.text.length),
      );
    }

    if (_projectFilesPathController.text != _controller.projectFilesPath) {
      _projectFilesPathController.text = _controller.projectFilesPath;
      _projectFilesPathController.selection = TextSelection.fromPosition(
        TextPosition(offset: _projectFilesPathController.text.length),
      );
    }
  }

  Widget _buildHeader() {
    final health = _controller.health;
    final ok = _readBool(health?['ok']) ?? false;
    final mode = _readString(health?['mode']) ?? 'неизвестно';
    final runningTasks = _readInt(health?['runningTasks']) ?? 0;
    final runningGraphRuns = _readInt(health?['runningGraphRuns']) ?? 0;
    final graphsCount = _readInt(health?['graphs']) ?? 0;
    final hasSelectedRun = _controller.activeRun != null;
    final sseConnected = _controller.runStreamConnected;
    final sseLabel = hasSelectedRun
        ? (sseConnected
              ? 'SSE запуска подключен'
              : 'SSE запуска отключен')
        : 'SSE не активен: выбери запуск';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Схема оркестрации',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Редактор канваса для оркестрации менеджер-воркер с обновлением статусов в реальном времени.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5A6B7D),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'URL оркестратора',
                      isDense: true,
                    ),
                    onSubmitted: (_) => unawaited(_reconnect()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _controller.reconnecting
                      ? null
                      : () => unawaited(_reconnect()),
                  icon: const Icon(Icons.link),
                  label: Text(
                    _controller.reconnecting ? 'Подключение' : 'Подключить',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed:
                      _controller.loadingHealth || _controller.loadingGraphs
                      ? null
                      : () => unawaited(_refreshAll()),
                  tooltip: 'Обновить состояние и список схем',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statusChip(
                  icon: ok ? Icons.check_circle : Icons.error_outline,
                  label: ok ? 'сервис: ok' : 'сервис: ошибка',
                  color: ok ? const Color(0xFF15703D) : const Color(0xFFA93B3B),
                  background: ok
                      ? const Color(0xFFE5F7EB)
                      : const Color(0xFFFFECEC),
                ),
                const SizedBox(width: 8),
                _statusChip(
                  icon: Icons.settings_ethernet,
                  label: 'режим: $mode',
                  color: const Color(0xFF2A5172),
                  background: const Color(0xFFE8F2FD),
                ),
                const SizedBox(width: 8),
                _statusChip(
                  icon: Icons.account_tree,
                  label: 'схем: $graphsCount',
                  color: const Color(0xFF5A4A1A),
                  background: const Color(0xFFFFF3D9),
                ),
                const SizedBox(width: 8),
                _statusChip(
                  icon: Icons.play_circle_outline,
                  label: 'запусков: $runningGraphRuns',
                  color: const Color(0xFF17567A),
                  background: const Color(0xFFE6F4FC),
                ),
                const SizedBox(width: 8),
                _statusChip(
                  icon: Icons.task_alt,
                  label: 'задач: $runningTasks',
                  color: const Color(0xFF214C67),
                  background: const Color(0xFFEBF3FA),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: sseConnected
                        ? const Color(0xFFDFF8E9)
                        : hasSelectedRun
                        ? const Color(0xFFEFF2F6)
                        : const Color(0xFFFFF6DD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sseConnected
                          ? const Color(0xFF98E0B0)
                          : hasSelectedRun
                          ? const Color(0xFFD3D9E2)
                          : const Color(0xFFE8D89A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        sseConnected
                            ? Icons.wifi
                            : Icons.wifi_off,
                        size: 14,
                        color: sseConnected
                            ? const Color(0xFF1B6A38)
                            : hasSelectedRun
                            ? const Color(0xFF657488)
                            : const Color(0xFF7A6A22),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        sseLabel,
                        style: TextStyle(
                          fontSize: 12,
                          color: sseConnected
                              ? const Color(0xFF1B6A38)
                              : hasSelectedRun
                              ? const Color(0xFF657488)
                              : const Color(0xFF7A6A22),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGraphsCard(),
              const SizedBox(height: 10),
              _buildPaletteCard(),
              const SizedBox(height: 10),
              _buildRunsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGraphsCard() {
    final selectedGraphId = _controller.activeGraphId;
    final revisionLabel = selectedGraphId == null
        ? 'локально'
        : '${_controller.graphRevision}';

    return _sectionCard(
      title: 'Состояние схемы',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: selectedGraphId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Схема в бэкенде',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _controller.availableGraphs
                .map(
                  (graph) => DropdownMenuItem<String>(
                    value: graph.id,
                    child: Text(
                      '${graph.name} (r${graph.latestRevision})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                unawaited(_controller.loadGraph(value));
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _graphNameController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Название схемы',
              isDense: true,
            ),
            onChanged: _controller.setGraphName,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _graphDescriptionController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Описание',
              isDense: true,
              alignLabelWithHint: true,
            ),
            onChanged: _controller.setGraphDescription,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _projectFilesPathController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Глобальная папка по умолчанию (optional)',
              hintText: r'C:\project\WhiteOps\Test_work',
              isDense: true,
            ),
            onChanged: _controller.setProjectFilesPath,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _controller.loadingGraphs
                      ? null
                      : () => unawaited(_controller.refreshGraphs()),
                  icon: const Icon(Icons.list),
                  label: const Text('Обновить'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _controller.savingGraph
                      ? null
                      : () => unawaited(_controller.saveGraphToBackend()),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Сохранить в API'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_controller.saveLocalDraft()),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Сохранить локально'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_controller.loadLocalDraft()),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Загрузить локально'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => unawaited(_showValidationResult()),
            icon: const Icon(Icons.rule),
            label: const Text('Проверить схему'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Узлы: ${_controller.nodes.length} | Связи: ${_controller.edges.length} | Рев: $revisionLabel',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF4D6077),
                  ),
                ),
              ),
              Switch(
                value: _controller.snapToGrid,
                onChanged: _controller.toggleSnapToGrid,
              ),
              const Text('Привязка', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteCard() {
    return _sectionCard(
      title: 'Палитра',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Перетащите карточку на канвас, чтобы добавить узел. Двойной клик по выходному порту, затем по входному для создания связи.',
            style: TextStyle(fontSize: 12, color: Color(0xFF5B6F85)),
          ),
          const SizedBox(height: 8),
          ..._controller.palette.map(_buildPaletteNodeTile),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _controller.selectedRelationType,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Тип связи по умолчанию',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: 'manager_to_worker',
                child: Text('Менеджер -> Воркер'),
              ),
              DropdownMenuItem(value: 'dependency', child: Text('Зависимость')),
              DropdownMenuItem(value: 'peer', child: Text('Равный')),
              DropdownMenuItem(
                value: 'feedback',
                child: Text('Обратная связь'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                _controller.setSelectedRelationType(value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteNodeTile(PaletteNodeTemplate template) {
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD2DFEE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator, color: Color(0xFF3B6586)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  template.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5A6C82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Draggable<PaletteNodeTemplate>(
      data: template,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 260, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.55, child: card),
      child: Tooltip(message: 'Перетащите на канвас', child: card),
    );
  }

  Widget _buildRunsCard() {
    final activeRun = _controller.activeRun;
    final selectedRunId = activeRun?.runId;

    return _sectionCard(
      title: 'Управление запуском',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _controller.runningGraph
                      ? null
                      : () => unawaited(_controller.startRun()),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    _controller.runningGraph ? 'Запуск' : 'Запустить схему',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _controller.stoppingRun
                      ? null
                      : () => unawaited(_controller.stopRun()),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(
                    _controller.stoppingRun ? 'Остановка' : 'Остановить запуск',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedRunId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Запуск',
                    isDense: true,
                  ),
                  items: _controller.availableRuns
                      .map(
                        (run) => DropdownMenuItem<String>(
                          value: run.runId,
                          child: Text(
                            '${graphRunStatusLabel(run.status)} | ${_short(run.runId)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(_controller.selectRun(value));
                    }
                  },
                ),
              ),
              IconButton(
                onPressed: () => unawaited(_controller.refreshRuns()),
                tooltip: 'Обновить запуски',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (activeRun == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Запуск не выбран.',
                style: TextStyle(color: Color(0xFF607287)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _runInfoChip('статус', graphRunStatusLabel(activeRun.status)),
                _runInfoChip('ревизия', '${activeRun.graphRevision}'),
                _runInfoChip(
                  'остановка',
                  activeRun.cancelRequested ? 'да' : 'нет',
                ),
                _runInfoChip('события', '${activeRun.events.length}'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _runInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD5E2F1)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, color: Color(0xFF3F5670)),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E3F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String text) {
    return Material(
      color: const Color(0xFFFFECEC),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Color(0xFF9E2121)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Color(0xFF7E2121)),
              ),
            ),
            TextButton(
              onPressed: _controller.clearError,
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner(String text) {
    return Material(
      color: const Color(0xFFE7F6ED),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF206042)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Color(0xFF23563E)),
              ),
            ),
            TextButton(
              onPressed: _controller.clearInfo,
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showValidationResult() async {
    final result = await _controller.validateGraph();
    if (!mounted || result == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(result.valid ? 'Схема валидна' : 'Схема невалидна'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Text(
                'Топологический порядок: ${result.topologicalOrder.join(', ')}\n\n'
                'Ошибки:\n${result.errors.isEmpty ? '-' : result.errors.join('\n')}\n\n'
                'Предупреждения:\n${result.warnings.isEmpty ? '-' : result.warnings.join('\n')}',
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openNodeDialog(GraphNodeModel node) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 900,
            height: 680,
            child: NodeDialogModal(controller: _controller, node: node),
          ),
        );
      },
    );
  }

  Future<void> _reconnect() async {
    await _controller.reconnect(_serverController.text);
    if (!mounted) {
      return;
    }
    _serverController.text = _controller.baseUrl;
  }

  Future<void> _refreshAll() async {
    await _controller.refreshHealth();
    await _controller.refreshGraphs();
    await _controller.refreshRuns();
  }

  String _short(String value) {
    if (value.length <= 8) {
      return value;
    }
    return value.substring(0, 8);
  }

  String? _readString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
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

  bool? _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    return null;
  }
}
