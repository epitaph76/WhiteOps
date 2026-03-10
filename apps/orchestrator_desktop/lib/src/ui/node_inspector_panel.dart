// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

import '../models/graph_editor_models.dart';

class NodeInspectorPayload {
  const NodeInspectorPayload({
    required this.label,
    required this.type,
    required this.agentId,
    required this.role,
    required this.cwd,
    required this.prompt,
    required this.timeoutMs,
    required this.maxRetries,
    required this.retryDelayMs,
  });

  final String label;
  final String type;
  final String agentId;
  final String role;
  final String? cwd;
  final String? prompt;
  final int? timeoutMs;
  final int? maxRetries;
  final int? retryDelayMs;
}

class NodeInspectorPanel extends StatefulWidget {
  const NodeInspectorPanel({
    required this.node,
    required this.nodeStatus,
    required this.onApply,
    required this.onOpenDialog,
    required this.onRunGraph,
    required this.onStopGraph,
    super.key,
  });

  final GraphNodeModel node;
  final String nodeStatus;
  final ValueChanged<NodeInspectorPayload> onApply;
  final VoidCallback onOpenDialog;
  final VoidCallback onRunGraph;
  final VoidCallback onStopGraph;

  @override
  State<NodeInspectorPanel> createState() => _NodeInspectorPanelState();
}

class _NodeInspectorPanelState extends State<NodeInspectorPanel> {
  late final TextEditingController _labelController;
  late final TextEditingController _cwdController;
  late final TextEditingController _promptController;
  late final TextEditingController _timeoutController;
  late final TextEditingController _retriesController;
  late final TextEditingController _retryDelayController;

  late String _type;
  late String _agentId;
  late String _role;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController();
    _cwdController = TextEditingController();
    _promptController = TextEditingController();
    _timeoutController = TextEditingController();
    _retriesController = TextEditingController();
    _retryDelayController = TextEditingController();
    _syncFromNode();
  }

  @override
  void didUpdateWidget(covariant NodeInspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.node.label != widget.node.label ||
        oldWidget.node.type != widget.node.type ||
        oldWidget.node.config.agentId != widget.node.config.agentId ||
        oldWidget.node.config.role != widget.node.config.role ||
        oldWidget.node.config.timeoutMs != widget.node.config.timeoutMs ||
        oldWidget.node.config.maxRetries != widget.node.config.maxRetries ||
        oldWidget.node.config.retryDelayMs != widget.node.config.retryDelayMs ||
        oldWidget.node.config.cwd != widget.node.config.cwd ||
        oldWidget.node.config.prompt != widget.node.config.prompt) {
      _syncFromNode();
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _cwdController.dispose();
    _promptController.dispose();
    _timeoutController.dispose();
    _retriesController.dispose();
    _retryDelayController.dispose();
    super.dispose();
  }

  void _syncFromNode() {
    final node = widget.node;
    _labelController.text = node.label;
    _cwdController.text = node.config.cwd ?? '';
    _promptController.text = node.config.prompt ?? '';
    _timeoutController.text = node.config.timeoutMs?.toString() ?? '';
    _retriesController.text = node.config.maxRetries?.toString() ?? '';
    _retryDelayController.text = node.config.retryDelayMs?.toString() ?? '';

    _type = node.type;
    _agentId = node.config.agentId;
    _role = node.config.role;
  }

  int? _readOptionalInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  void _apply() {
    widget.onApply(
      NodeInspectorPayload(
        label: _labelController.text.trim().isEmpty
            ? widget.node.label
            : _labelController.text.trim(),
        type: _type,
        agentId: _agentId,
        role: _role,
        cwd: _cwdController.text.trim().isEmpty
            ? null
            : _cwdController.text.trim(),
        prompt: _promptController.text.trim().isEmpty
            ? null
            : _promptController.text.trim(),
        timeoutMs: _readOptionalInt(_timeoutController.text),
        maxRetries: _readOptionalInt(_retriesController.text),
        retryDelayMs: _readOptionalInt(_retryDelayController.text),
      ),
    );
  }

  Widget _buildTypeAndAgentFields() {
    Widget typeField() {
      return DropdownButtonFormField<String>(
        isExpanded: true,
        value: _type,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Тип',
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(
            value: 'manager',
            child: Text('Менеджер (manager)'),
          ),
          DropdownMenuItem(
            value: 'worker',
            child: Text('Воркер (worker)'),
          ),
          DropdownMenuItem(
            value: 'agent',
            child: Text('Агент (agent)'),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _type = value;
            });
          }
        },
      );
    }

    Widget agentField() {
      return DropdownButtonFormField<String>(
        isExpanded: true,
        value: _agentId,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Агент',
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(value: 'codex', child: Text('codex')),
          DropdownMenuItem(value: 'qwen', child: Text('qwen')),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _agentId = value;
            });
          }
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              typeField(),
              const SizedBox(height: 8),
              agentField(),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: typeField()),
            const SizedBox(width: 8),
            Expanded(child: agentField()),
          ],
        );
      },
    );
  }

  Widget _buildTimingFields() {
    Widget timeoutField() {
      return TextFormField(
        controller: _timeoutController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Таймаут (мс)',
          isDense: true,
        ),
      );
    }

    Widget retriesField() {
      return TextFormField(
        controller: _retriesController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Повторы',
          isDense: true,
        ),
      );
    }

    Widget retryDelayField() {
      return TextFormField(
        controller: _retryDelayController,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Задержка повтора (мс)',
          isDense: true,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              timeoutField(),
              const SizedBox(height: 8),
              retriesField(),
              const SizedBox(height: 8),
              retryDelayField(),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: timeoutField()),
            const SizedBox(width: 8),
            Expanded(child: retriesField()),
            const SizedBox(width: 8),
            Expanded(child: retryDelayField()),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ID узла: ${widget.node.id}',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF5A6C84)),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _labelController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Название',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        _buildTypeAndAgentFields(),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: _role,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Роль',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(
              value: 'manager',
              child: Text('Менеджер (manager)'),
            ),
            DropdownMenuItem(value: 'worker', child: Text('Воркер (worker)')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _role = value;
              });
            }
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _cwdController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Рабочая папка (cwd)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _promptController,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Промпт',
            alignLabelWithHint: true,
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        _buildTimingFields(),
        const SizedBox(height: 8),
        Text(
          'Статус: ${nodeExecutionStatusLabel(widget.nodeStatus)}',
          style: TextStyle(
            fontSize: 12,
            color: _statusColor(widget.nodeStatus),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _apply,
                icon: const Icon(Icons.save),
                label: const Text('Применить'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: widget.onOpenDialog,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Открыть диалог'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onRunGraph,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Запустить'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onStopGraph,
                icon: const Icon(Icons.stop),
                label: const Text('Остановить'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
        return const Color(0xFF0E5D50);
      case 'completed':
        return const Color(0xFF176C2D);
      case 'failed':
        return const Color(0xFF902A2A);
      case 'canceled':
      case 'skipped':
        return const Color(0xFF7C5A1A);
      case 'retrying':
        return const Color(0xFF7A5200);
      case 'ready':
        return const Color(0xFF1E5F8A);
      default:
        return const Color(0xFF556882);
    }
  }
}

