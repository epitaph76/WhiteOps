// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/graph_editor_models.dart';
import '../state/graph_editor_controller.dart';
import 'graph_canvas_view.dart';
import 'graph_ui_models.dart';
import 'make_tokens.dart';
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
                      colors: [
                        MakeTokens.shellBg,
                        MakeTokens.shellBg2,
                        MakeTokens.shellAccent,
                      ],
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
        ? (sseConnected ? 'SSE запуска подключен' : 'SSE запуска отключен')
        : 'SSE не активен: выбери запуск';

    return GlassCard(
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
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: MakeTokens.text,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Desktop graph editor with live run and SSE monitoring.',
                      style: TextStyle(fontSize: 12, color: MakeTokens.muted),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'Orchestrator URL',
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
                  _controller.reconnecting ? 'Connecting' : 'Connect',
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed:
                    _controller.loadingHealth || _controller.loadingGraphs
                    ? null
                    : () => unawaited(_refreshAll()),
                tooltip: 'Refresh state and graph list',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statusChip(
                icon: ok ? Icons.check_circle : Icons.error_outline,
                label: ok ? 'service: ok' : 'service: error',
                color: ok ? const Color(0xFF15703D) : const Color(0xFFA93B3B),
                background: ok
                    ? const Color(0xFFE5F7EB)
                    : const Color(0xFFFFECEC),
              ),
              const SizedBox(width: 8),
              _statusChip(
                icon: Icons.settings_ethernet,
                label: 'mode: $mode',
                color: const Color(0xFF2A5172),
                background: const Color(0xFFE8F2FD),
              ),
              const SizedBox(width: 8),
              _statusChip(
                icon: Icons.account_tree,
                label: 'graphs: $graphsCount',
                color: const Color(0xFF5A4A1A),
                background: const Color(0xFFFFF3D9),
              ),
              const SizedBox(width: 8),
              _statusChip(
                icon: Icons.play_circle_outline,
                label: 'runs: $runningGraphRuns',
                color: const Color(0xFF17567A),
                background: const Color(0xFFE6F4FC),
              ),
              const SizedBox(width: 8),
              _statusChip(
                icon: Icons.task_alt,
                label: 'tasks: $runningTasks',
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
                      sseConnected ? Icons.wifi : Icons.wifi_off,
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
    );
  }

  Widget _buildSidebar() {
    return GlassCard(
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_showSavedGraphsDialog()),
                  icon: const Icon(Icons.view_list),
                  label: const Text('Saved graphs'),
                ),
              ),
            ],
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
                      : () => unawaited(_controller.refreshLocalSavedGraphs()),
                  icon: const Icon(Icons.list),
                  label: const Text('Local list'),
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

  Widget _buildSavedGraphsList(String? selectedGraphId) {
    final graphs = _controller.localSavedGraphs;
    if (graphs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F7FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD4E1EF)),
        ),
        child: const Text(
          'No local saved graphs yet. Save current canvas locally to create one.',
          style: TextStyle(fontSize: 12, color: Color(0xFF51657B)),
        ),
      );
    }

    return ListView.separated(
      itemCount: graphs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
          final graph = graphs[index];
          final selected = graph.id == selectedGraphId;

          return Material(
            color: selected ? const Color(0xFFE9F4FF) : const Color(0xFFF7FAFD),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                await _controller.loadLocalSavedGraph(graph.id);
                if (!mounted) {
                  return;
                }
                Navigator.of(this.context).maybePop();
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF7EB2E9)
                        : const Color(0xFFD3E0EE),
                    width: selected ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            graph.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF24415F),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${graph.nodes.length} nodes, ${graph.edges.length} edges',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF5A7088),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete local graph',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete local graph?'),
                            content: Text(
                              'Delete "${graph.name}" from local saved list?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await _controller.deleteLocalSavedGraph(graph.id);
                        }
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Color(0xFF8E3A3A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 116,
                      height: 66,
                      child: _GraphPreviewBox(
                        nodes: graph.nodes,
                        edges: graph.edges,
                        selected: selected,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
      },
    );
  }

  Future<void> _showSavedGraphsDialog() async {
    await _controller.refreshLocalSavedGraphs(showLoading: false);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 760,
            height: 520,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Local saved graphs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => _buildSavedGraphsList(
                        _controller.activeLocalGraphId,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _controller.loadingGraphs
                              ? null
                              : () =>
                                  unawaited(_controller.refreshLocalSavedGraphs()),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaletteCard() {
    return _sectionCard(
      title: 'Palette',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Drag a card onto canvas to add a node. Then connect nodes from output to input.',
            style: TextStyle(fontSize: 12, color: Color(0xFF5B6F85)),
          ),
          const SizedBox(height: 8),
          ..._controller.palette
              .where((template) => template.key != 'generic-agent')
              .map(_buildPaletteNodeTile),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => unawaited(_showCreateAgentDialog()),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create model node'),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _controller.selectedRelationType,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Default relation type',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: 'manager_to_worker',
                child: Text('Manager -> Worker'),
              ),
              DropdownMenuItem(value: 'dependency', child: Text('Dependency')),
              DropdownMenuItem(value: 'peer', child: Text('Peer')),
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
      child: Tooltip(message: 'Drop on canvas', child: card),
    );
  }

  Widget _buildRunsCard() {
    final activeRun = _controller.activeRun;
    final selectedRunId = activeRun?.runId;

    return _sectionCard(
      title: 'Run control',
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
                    _controller.runningGraph ? 'Starting' : 'Run graph',
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
                    _controller.stoppingRun ? 'Stopping' : 'Stop run',
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
                    labelText: 'Run',
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
                tooltip: 'Refresh runs',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (activeRun == null)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No run selected.',
                style: TextStyle(color: Color(0xFF607287)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _runInfoChip('status', graphRunStatusLabel(activeRun.status)),
                _runInfoChip('revision', '${activeRun.graphRevision}'),
                _runInfoChip(
                  'cancel',
                  activeRun.cancelRequested ? 'yes' : 'no',
                ),
                _runInfoChip('events', '${activeRun.events.length}'),
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
    return SectionCard(title: title, child: child);
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
        border: Border.all(color: MakeTokens.border),
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

  Future<void> _showCreateAgentDialog() async {
    var selectedModel = 'qwen';
    var selectedRole = 'worker';
    final customPromptController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: 620,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Создать модель агента',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: selectedModel,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Модель',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'qwen', child: Text('Qwen')),
                          DropdownMenuItem(
                            value: 'codex',
                            child: Text('Codex'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedModel = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Роль',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'manager',
                            child: Text('Менеджер'),
                          ),
                          DropdownMenuItem(
                            value: 'worker',
                            child: Text('Воркер'),
                          ),
                          DropdownMenuItem(
                            value: 'reviewer',
                            child: Text('Ревьюер'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedRole = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: customPromptController,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Custom prompt',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Отмена'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () {
                              _controller.addConfiguredAgentNode(
                                modelId: selectedModel,
                                role: selectedRole,
                                customSystemPrompt: customPromptController.text,
                              );
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Создать'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    customPromptController.dispose();
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

class _GraphPreviewBox extends StatelessWidget {
  const _GraphPreviewBox({
    required this.nodes,
    required this.edges,
    required this.selected,
  });

  final List<GraphNodeModel> nodes;
  final List<GraphEdgeModel> edges;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEFF7FF) : const Color(0xFFF2F6FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFF98BDE7) : const Color(0xFFD0DDEB),
        ),
      ),
      child: CustomPaint(
        painter: _GraphPreviewPainter(
          nodes: nodes,
          edges: edges,
        ),
      ),
    );
  }
}

class _GraphPreviewPainter extends CustomPainter {
  _GraphPreviewPainter({required this.nodes, required this.edges});

  final List<GraphNodeModel> nodes;
  final List<GraphEdgeModel> edges;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      background,
    );

    if (nodes.isEmpty) {
      return;
    }

    final nodeById = <String, GraphNodeModel>{
      for (final node in nodes) node.id: node,
    };

    var minX = nodes.first.x;
    var maxX = nodes.first.x;
    var minY = nodes.first.y;
    var maxY = nodes.first.y;

    for (final node in nodes.skip(1)) {
      minX = math.min(minX, node.x);
      maxX = math.max(maxX, node.x);
      minY = math.min(minY, node.y);
      maxY = math.max(maxY, node.y);
    }

    const nodePreviewWidth = 24.0;
    const nodePreviewHeight = 14.0;
    final dataWidth = math.max(1.0, (maxX - minX) + nodePreviewWidth);
    final dataHeight = math.max(1.0, (maxY - minY) + nodePreviewHeight);
    final scale = math.min(
      (size.width - 10) / dataWidth,
      (size.height - 10) / dataHeight,
    );

    final offsetX = (size.width - (dataWidth * scale)) / 2;
    final offsetY = (size.height - (dataHeight * scale)) / 2;

    Offset mapPoint(double x, double y) {
      final px = offsetX + (x - minX) * scale;
      final py = offsetY + (y - minY) * scale;
      return Offset(px, py);
    }

    final edgePaint = Paint()
      ..color = const Color(0xFF8FA5BC)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final from = nodeById[edge.fromNodeId];
      final to = nodeById[edge.toNodeId];
      if (from == null || to == null) {
        continue;
      }

      final start = mapPoint(
        from.x + (nodePreviewWidth / 2),
        from.y + (nodePreviewHeight / 2),
      );
      final end = mapPoint(
        to.x + (nodePreviewWidth / 2),
        to.y + (nodePreviewHeight / 2),
      );
      canvas.drawLine(start, end, edgePaint);
    }

    final nodePaint = Paint()..color = const Color(0xFF3D73A8);
    for (final node in nodes) {
      final topLeft = mapPoint(node.x, node.y);
      final rect = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        nodePreviewWidth * scale,
        nodePreviewHeight * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        nodePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPreviewPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.edges != edges;
  }
}

