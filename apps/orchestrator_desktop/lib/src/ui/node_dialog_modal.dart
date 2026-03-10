import 'dart:async';

import 'package:flutter/material.dart';

import '../models/graph_editor_models.dart';
import '../state/graph_editor_controller.dart';

class NodeDialogModal extends StatefulWidget {
  const NodeDialogModal({
    required this.controller,
    required this.node,
    super.key,
  });

  final GraphEditorController controller;
  final GraphNodeModel node;

  @override
  State<NodeDialogModal> createState() => _NodeDialogModalState();
}

class _NodeDialogModalState extends State<NodeDialogModal> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadNodeDialogData(widget.node.id));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final liveNode = widget.controller.nodes
            .where((item) => item.id == widget.node.id)
            .firstOrNull;
        final fullAccess = liveNode?.config.fullAccess ?? widget.node.config.fullAccess;
        final messages =
            widget.controller.nodeMessages[widget.node.id] ??
            const <NodeChatMessageModel>[];
        final logs =
            widget.controller.nodeLogs[widget.node.id] ??
            const <NodeLogEntryModel>[];
        final nodeState = widget.controller.activeRun?.nodeStates[widget.node.id];

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Диалог узла: ${widget.node.label}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => unawaited(
                      widget.controller.loadNodeDialogData(widget.node.id),
                    ),
                    tooltip: 'Обновить чат и логи',
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7FC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD7E3F1)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Полный доступ (danger-full-access) для запуска этого узла',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: fullAccess,
                      onChanged: (value) {
                        widget.controller.updateNode(
                          widget.node.id,
                          fullAccess: value,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _panel(
                        title: 'Чат',
                        child: Column(
                          children: [
                            Expanded(
                              child: messages.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Сообщений пока нет.',
                                        style: TextStyle(
                                          color: Color(0xFF5C6F86),
                                        ),
                                      ),
                                    )
                                  : SelectionArea(
                                      child: ListView.separated(
                                        itemCount: messages.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final message = messages[index];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                              horizontal: 4,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SelectableText(
                                                  '${_roleLabel(message.role)}: ${message.text}',
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                SelectableText(
                                                  _formatDateTime(
                                                    message.createdAt,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF667B93),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _messageController,
                                    minLines: 1,
                                    maxLines: 3,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      labelText: 'Сообщение узлу',
                                      isDense: true,
                                    ),
                                    onSubmitted: (_) =>
                                        unawaited(_sendMessage()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed:
                                      widget.controller.sendingNodeMessage
                                      ? null
                                      : () => unawaited(_sendMessage()),
                                  icon: const Icon(Icons.send),
                                  label: Text(
                                    widget.controller.sendingNodeMessage
                                        ? 'Отправка'
                                        : 'Отправить',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _panel(
                        title: 'Вывод модели',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F7FC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFD7E3F1),
                                ),
                              ),
                              child: Text(
                                'Статус: ${nodeExecutionStatusLabel(nodeState?.status ?? 'pending')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _statusColor(nodeState?.status ?? 'pending'),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: logs.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Логов пока нет.',
                                        style: TextStyle(color: Color(0xFF5D7088)),
                                      ),
                                    )
                                  : SelectionArea(
                                      child: ListView.separated(
                                        itemCount: logs.length,
                                        separatorBuilder: (_, _) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final item = logs[index];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                              horizontal: 4,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SelectableText(
                                                  '[${item.stream}] ${item.chunk}',
                                                  style: const TextStyle(
                                                    fontFamily: 'Consolas',
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                SelectableText(
                                                  '#${item.sequence} | ${_formatDateTime(item.createdAt)}',
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    color: Color(0xFF667B93),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                            if (nodeState != null) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 130,
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    prettyJson({
                                      'status': nodeState.status,
                                      'attempts': nodeState.attempts,
                                      'lastError': nodeState.lastError,
                                      'lastPrompt': nodeState.lastPrompt,
                                      'result': nodeState.result,
                                    }),
                                    style: const TextStyle(
                                      fontFamily: 'Consolas',
                                      fontSize: 11,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4E2F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text;
    final sent = await widget.controller.sendMessageToNode(widget.node.id, message);
    if (!mounted) {
      return;
    }
    if (sent) {
      _messageController.clear();
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'user':
        return 'Пользователь';
      case 'assistant':
        return 'Ассистент';
      case 'system':
        return 'Система';
      default:
        return role;
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }

    final local = value.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');

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
