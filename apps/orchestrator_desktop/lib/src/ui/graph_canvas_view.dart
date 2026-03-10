// ignore_for_file: deprecated_member_use
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/graph_editor_models.dart';
import '../state/graph_editor_controller.dart';
import 'graph_ui_models.dart';

class GraphCanvasView extends StatefulWidget {
  const GraphCanvasView({
    required this.controller,
    required this.onNodeDoubleTap,
    super.key,
  });

  final GraphEditorController controller;
  final ValueChanged<GraphNodeModel> onNodeDoubleTap;

  @override
  State<GraphCanvasView> createState() => _GraphCanvasViewState();
}

class _GraphCanvasViewState extends State<GraphCanvasView> {
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  String? _connectingFromNodeId;
  Offset? _connectingPointerScene;
  Offset? _lastConnectionGlobal;

  @override
  void initState() {
    super.initState();
    _transformationController.value = Matrix4.identity()
      ..translate(160.0, 120.0)
      ..scale(1.0);
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    if (!mounted) {
      return;
    }

    final connectionGlobal = _lastConnectionGlobal;
    if (connectionGlobal != null) {
      try {
        _connectingPointerScene = _globalToScene(connectionGlobal);
      } catch (_) {
        // Viewer can be transiently unavailable during relayout.
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          return Stack(
            children: [
              DragTarget<PaletteNodeTemplate>(
                onWillAcceptWithDetails: (_) => true,
                onAcceptWithDetails: (details) {
                  _handleTemplateDrop(details.data, details.offset);
                },
                builder: (context, candidateData, _) {
                  final isDropHover = candidateData.isNotEmpty;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: isDropHover
                        ? BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF2C7FB8),
                              width: 2,
                            ),
                          )
                        : null,
                    child: MouseRegion(
                      onHover: (event) {
                        if (_connectingFromNodeId == null) {
                          return;
                        }
                        _updateConnectionPointer(event.position);
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _handleCanvasTap(details.globalPosition),
                        child: InteractiveViewer(
                          key: _viewerKey,
                          transformationController: _transformationController,
                          minScale: 0.2,
                          maxScale: 2.6,
                          boundaryMargin: const EdgeInsets.all(900),
                          constrained: false,
                          panEnabled: _connectingFromNodeId == null,
                          scaleEnabled: _connectingFromNodeId == null,
                          child: SizedBox(
                            width: graphCanvasWidth,
                            height: graphCanvasHeight,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: GraphCanvasPainter(
                                      nodes: widget.controller.nodes,
                                      edges: widget.controller.edges,
                                      selectedEdgeId:
                                          widget.controller.selectedEdgeId,
                                      tempEdge: _buildTempEdge(),
                                    ),
                                  ),
                                ),
                                ...widget.controller.nodes.map(
                                  _buildNodePositioned,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _buildMiniMap(viewportSize),
              ),
              Positioned(left: 12, bottom: 12, child: _buildCanvasToolbar()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCanvasToolbar() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    return Material(
      elevation: 3,
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _zoomBy(0.9),
              icon: const Icon(Icons.remove),
              tooltip: 'Уменьшить',
            ),
            SizedBox(
              width: 62,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _zoomBy(1.1),
              icon: const Icon(Icons.add),
              tooltip: 'Увеличить',
            ),
            const VerticalDivider(width: 18, thickness: 1),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _resetView,
              icon: const Icon(Icons.center_focus_strong),
              tooltip: 'Сбросить вид',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniMap(Size viewportSize) {
    final sceneViewport = _sceneViewportRect(viewportSize);
    return Container(
      width: 220,
      height: 148,
      decoration: BoxDecoration(
        color: const Color(0xECFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCCD7E4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: MiniMapPainter(
            nodes: widget.controller.nodes,
            viewport: sceneViewport,
          ),
        ),
      ),
    );
  }

  Widget _buildNodePositioned(GraphNodeModel node) {
    final selected = widget.controller.selectedNodeIds.contains(node.id);
    final status = widget.controller.nodeStatus(node.id);
    final error = widget.controller.nodeError(node.id);

    return Positioned(
      left: node.x,
      top: node.y,
      width: graphNodeWidth,
      height: graphNodeHeight,
      child: GraphNodeCard(
        node: node,
        selected: selected,
        status: status,
        errorText: error,
        onTap: () {
          final additive = _isAdditiveSelectionPressed();
          widget.controller.selectNode(
            node.id,
            additive: additive,
            toggle: additive,
          );
        },
        onDoubleTap: () => widget.onNodeDoubleTap(node),
        onPanStart: () {
          if (_connectingFromNodeId != null) {
            return;
          }
          final additive = _isAdditiveSelectionPressed();
          if (!widget.controller.selectedNodeIds.contains(node.id)) {
            widget.controller.selectNode(
              node.id,
              additive: additive,
              toggle: additive,
            );
          }
        },
        onPanUpdate: (delta) {
          if (_connectingFromNodeId != null) {
            return;
          }
          final scale = _transformationController.value.getMaxScaleOnAxis();
          final adjusted = delta / math.max(scale, 0.0001);
          widget.controller.moveSelectedNodes(adjusted.dx, adjusted.dy);
        },
        onOutputConnectStart: (globalPosition) =>
            _armConnection(node.id, globalPosition),
        onOutputConnectUpdate: _updateConnectionPointer,
        onOutputConnectEnd: _completeConnectionByPointer,
        onOutputConnectCancel: _cancelConnection,
        onInputDoubleTap: () {
          _completeConnectionTo(node.id);
        },
        extraOutputPorts: 0,
      ),
    );
  }

  TempEdge? _buildTempEdge() {
    final fromNodeId = _connectingFromNodeId;
    final pointer = _connectingPointerScene;
    if (fromNodeId == null || pointer == null) {
      return null;
    }

    final fromNode = widget.controller.nodes
        .where((node) => node.id == fromNodeId)
        .firstOrNull;
    if (fromNode == null) {
      return null;
    }

    final start = Offset(
      fromNode.x + graphNodeWidth,
      fromNode.y + graphNodePortCenterY,
    );

    return TempEdge(
      from: start,
      to: pointer,
      relationType: widget.controller.selectedRelationType,
    );
  }

  void _handleCanvasTap(Offset globalPosition) {
    if (_connectingFromNodeId != null) {
      _cancelConnection();
      return;
    }

    final scene = _globalToScene(globalPosition);
    final edge = _findEdgeNearPoint(scene);
    if (edge != null) {
      widget.controller.selectEdge(edge.id);
      return;
    }
    widget.controller.clearSelection();
  }

  void _armConnection(String fromNodeId, Offset globalPosition) {
    _connectingFromNodeId = fromNodeId;
    _updateConnectionPointer(globalPosition);
  }

  void _completeConnectionTo(String toNodeId) {
    final fromNodeId = _connectingFromNodeId;
    _cancelConnection();

    if (fromNodeId == null || fromNodeId == toNodeId) {
      return;
    }

    widget.controller.createEdge(
      fromNodeId,
      toNodeId,
      relationType: widget.controller.selectedRelationType,
    );
  }

  void _cancelConnection() {
    _connectingFromNodeId = null;
    _connectingPointerScene = null;
    _lastConnectionGlobal = null;
    setState(() {});
  }

  void _updateConnectionPointer(Offset globalPosition) {
    _lastConnectionGlobal = globalPosition;
    _connectingPointerScene = _globalToScene(globalPosition);
    setState(() {});
  }

  void _completeConnectionByPointer() {
    final scene = _connectingPointerScene;
    if (scene == null) {
      _cancelConnection();
      return;
    }
    final target = _findNodeAtScene(scene);
    if (target != null) {
      _completeConnectionTo(target.id);
      return;
    }
    _cancelConnection();
  }

  void _handleTemplateDrop(
    PaletteNodeTemplate template,
    Offset globalPosition,
  ) {
    final scene = _globalToScene(globalPosition);
    final dropX = scene.dx - (graphNodeWidth / 2);
    final dropY = scene.dy - (graphNodeHeight / 2);
    widget.controller.addNodeFromTemplate(template, dropX, dropY);
  }

  void _zoomBy(double factor) {
    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(0.2, 2.6);
    final adjustment = targetScale / math.max(currentScale, 0.0001);

    final center = _viewerCenterInScene();
    matrix.translate(center.dx, center.dy);
    matrix.scale(adjustment);
    matrix.translate(-center.dx, -center.dy);

    _transformationController.value = matrix;
    setState(() {});
  }

  void _resetView() {
    _transformationController.value = Matrix4.identity()
      ..translate(160.0, 120.0)
      ..scale(1.0);
    setState(() {});
  }

  bool _isAdditiveSelectionPressed() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
  }

  Offset _viewerCenterInScene() {
    final box = _viewerBox();
    final localCenter = box.size.center(Offset.zero);
    return _transformationController.toScene(localCenter);
  }

  Rect _sceneViewportRect(Size viewportSize) {
    try {
      final topLeft = _transformationController.toScene(Offset.zero);
      final bottomRight = _transformationController.toScene(
        Offset(viewportSize.width, viewportSize.height),
      );
      return Rect.fromPoints(topLeft, bottomRight);
    } catch (_) {
      return Rect.fromLTWH(0, 0, viewportSize.width, viewportSize.height);
    }
  }

  RenderBox _viewerBox() {
    final context = _viewerKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject;
    }

    throw StateError('RenderBox канваса недоступен.');
  }

  Offset _globalToScene(Offset globalPosition) {
    final box = _viewerBox();
    final local = box.globalToLocal(globalPosition);
    return _transformationController.toScene(local);
  }

  GraphEdgeModel? _findEdgeNearPoint(Offset scenePoint) {
    const hitDistance = 8.0;

    GraphEdgeModel? best;
    var bestDistance = double.infinity;

    for (final edge in widget.controller.edges) {
      final from = widget.controller.nodes
          .where((node) => node.id == edge.fromNodeId)
          .firstOrNull;
      final to = widget.controller.nodes
          .where((node) => node.id == edge.toNodeId)
          .firstOrNull;
      if (from == null || to == null) {
        continue;
      }

      final start = Offset(
        from.x + graphNodeWidth,
        from.y + graphNodePortCenterY,
      );
      final end = Offset(to.x, to.y + graphNodePortCenterY);
      final c1 = Offset(start.dx + 80, start.dy);
      final c2 = Offset(end.dx - 80, end.dy);
      final distance = _distanceToBezier(scenePoint, start, c1, c2, end);
      if (distance < hitDistance && distance < bestDistance) {
        best = edge;
        bestDistance = distance;
      }
    }

    return best;
  }

  GraphNodeModel? _findNodeAtScene(Offset scenePoint) {
    for (final node in widget.controller.nodes.reversed) {
      final rect = Rect.fromLTWH(node.x, node.y, graphNodeWidth, graphNodeHeight);
      if (rect.contains(scenePoint)) {
        return node;
      }
    }
    return null;
  }

  double _distanceToBezier(
    Offset point,
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
  ) {
    var best = double.infinity;
    const steps = 26;

    for (var i = 0; i <= steps; i += 1) {
      final t = i / steps;
      final sample = _cubicAt(p0, p1, p2, p3, t);
      final distance = (sample - point).distance;
      if (distance < best) {
        best = distance;
      }
    }
    return best;
  }

  Offset _cubicAt(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final inverse = 1 - t;
    return p0 * (inverse * inverse * inverse) +
        p1 * (3 * inverse * inverse * t) +
        p2 * (3 * inverse * t * t) +
        p3 * (t * t * t);
  }
}

class GraphNodeCard extends StatelessWidget {
  const GraphNodeCard({
    required this.node,
    required this.selected,
    required this.status,
    required this.errorText,
    required this.onTap,
    required this.onDoubleTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onOutputConnectStart,
    required this.onOutputConnectUpdate,
    required this.onOutputConnectEnd,
    required this.onOutputConnectCancel,
    required this.extraOutputPorts,
    required this.onInputDoubleTap,
    super.key,
  });

  final GraphNodeModel node;
  final bool selected;
  final String status;
  final String? errorText;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final ValueChanged<Offset> onOutputConnectStart;
  final ValueChanged<Offset> onOutputConnectUpdate;
  final VoidCallback onOutputConnectEnd;
  final VoidCallback onOutputConnectCancel;
  final int extraOutputPorts;
  final VoidCallback onInputDoubleTap;

  @override
  Widget build(BuildContext context) {
    final palette = _nodePalette(status);

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onPanStart: (_) => onPanStart(),
      onPanUpdate: (details) => onPanUpdate(details.delta),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7F4FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF2D7CB8) : const Color(0xFFC8D7E8),
            width: selected ? 2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -8,
              top: 46,
              child: GestureDetector(
                onDoubleTap: onInputDoubleTap,
                child: _PortDot(
                  color: const Color(0xFF3F6282),
                  tooltip: 'Входной порт (двойной клик для связи)',
                ),
              ),
            ),
            Positioned(
              right: -8,
              top: 46,
              child: GestureDetector(
                onPanStart: (details) =>
                    onOutputConnectStart(details.globalPosition),
                onPanUpdate: (details) =>
                    onOutputConnectUpdate(details.globalPosition),
                onPanEnd: (_) => onOutputConnectEnd(),
                onPanCancel: onOutputConnectCancel,
                child: _PortDot(
                  color: const Color(0xFF1D7F76),
                  tooltip: 'Выходной порт (зажмите и тяните для связи)',
                ),
              ),
            ),
            for (var index = 0; index < extraOutputPorts; index += 1)
              Positioned(
                right: -8,
                top: 74 + (index * 22),
                child: GestureDetector(
                  onPanStart: (details) =>
                      onOutputConnectStart(details.globalPosition),
                  onPanUpdate: (details) =>
                      onOutputConnectUpdate(details.globalPosition),
                  onPanEnd: (_) => onOutputConnectEnd(),
                  onPanCancel: onOutputConnectCancel,
                  child: const _PortDot(
                    color: Color(0xFF5A7F2A),
                    tooltip:
                        'Дополнительный порт менеджера (зажмите и тяните для связи)',
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${node.type} | ${node.config.agentId} / ${node.config.role}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF596B82),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.border),
                  ),
                  child: Text(
                    nodeExecutionStatusLabel(status),
                    style: TextStyle(
                      fontSize: 11,
                      color: palette.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'таймаут: ${node.config.timeoutMs ?? '-'} мс | повторы: ${node.config.maxRetries ?? 0}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF607286),
                  ),
                ),
                if (errorText != null && errorText!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    errorText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF8E2A2A),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  _BadgePalette _nodePalette(String value) {
    switch (value) {
      case 'ready':
        return const _BadgePalette(
          foreground: Color(0xFF165E8B),
          background: Color(0xFFE2F1FC),
          border: Color(0xFFA7D0ED),
        );
      case 'running':
        return const _BadgePalette(
          foreground: Color(0xFF115C4F),
          background: Color(0xFFDDF8F2),
          border: Color(0xFF97DEC9),
        );
      case 'retrying':
        return const _BadgePalette(
          foreground: Color(0xFF7B5306),
          background: Color(0xFFFFF1D8),
          border: Color(0xFFFFD58D),
        );
      case 'completed':
        return const _BadgePalette(
          foreground: Color(0xFF106A26),
          background: Color(0xFFDDF9E3),
          border: Color(0xFFA1E1AF),
        );
      case 'failed':
        return const _BadgePalette(
          foreground: Color(0xFF8E2222),
          background: Color(0xFFFFE8E8),
          border: Color(0xFFF2AEAE),
        );
      case 'canceled':
      case 'skipped':
        return const _BadgePalette(
          foreground: Color(0xFF70510D),
          background: Color(0xFFFFF0D4),
          border: Color(0xFFFFCF89),
        );
      default:
        return const _BadgePalette(
          foreground: Color(0xFF52617A),
          background: Color(0xFFEDF2F8),
          border: Color(0xFFD1DAE6),
        );
    }
  }
}

class _PortDot extends StatelessWidget {
  const _PortDot({required this.color, required this.tooltip});

  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.4),
        ),
      ),
    );
  }
}

class _BadgePalette {
  const _BadgePalette({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}

class TempEdge {
  const TempEdge({
    required this.from,
    required this.to,
    required this.relationType,
  });

  final Offset from;
  final Offset to;
  final String relationType;
}

class GraphCanvasPainter extends CustomPainter {
  const GraphCanvasPainter({
    required this.nodes,
    required this.edges,
    required this.selectedEdgeId,
    required this.tempEdge,
  });

  final List<GraphNodeModel> nodes;
  final List<GraphEdgeModel> edges;
  final String? selectedEdgeId;
  final TempEdge? tempEdge;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintEdges(canvas);
    if (tempEdge != null) {
      _paintTempEdge(canvas, tempEdge!);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0xFFEBF1F7)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0xFFD8E3EE)
      ..strokeWidth = 1.4;

    for (double x = 0; x <= size.width; x += GraphEditorController.gridSize) {
      final paint = (x / GraphEditorController.gridSize).round() % 5 == 0
          ? major
          : minor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y <= size.height; y += GraphEditorController.gridSize) {
      final paint = (y / GraphEditorController.gridSize).round() % 5 == 0
          ? major
          : minor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintEdges(Canvas canvas) {
    final nodeMap = {for (final node in nodes) node.id: node};

    for (final edge in edges) {
      final from = nodeMap[edge.fromNodeId];
      final to = nodeMap[edge.toNodeId];
      if (from == null || to == null) {
        continue;
      }

      final start = Offset(
        from.x + graphNodeWidth,
        from.y + graphNodePortCenterY,
      );
      final end = Offset(to.x, to.y + graphNodePortCenterY);

      final c1 = Offset(start.dx + 80, start.dy);
      final c2 = Offset(end.dx - 80, end.dy);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

      final isSelected = edge.id == selectedEdgeId;
      final paint = Paint()
        ..color = _edgeColor(edge.relationType, selected: isSelected)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.2 : 2.0;

      canvas.drawPath(path, paint);
      _drawArrow(canvas, end, c2, paint.color, isSelected ? 8 : 7);
      _drawEdgeLabel(canvas, edge, path, isSelected);
    }
  }

  void _paintTempEdge(Canvas canvas, TempEdge edge) {
    final paint = Paint()
      ..color = const Color(0xCC167E75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final c1 = Offset(edge.from.dx + 70, edge.from.dy);
    final c2 = Offset(edge.to.dx - 70, edge.to.dy);

    final path = Path()
      ..moveTo(edge.from.dx, edge.from.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, edge.to.dx, edge.to.dy);

    canvas.drawPath(path, paint);
    _drawArrow(canvas, edge.to, c2, paint.color, 7.5);
  }

  void _drawArrow(
    Canvas canvas,
    Offset tip,
    Offset control,
    Color color,
    double size,
  ) {
    final angle = math.atan2(tip.dy - control.dy, tip.dx - control.dx);
    final left =
        tip - Offset(math.cos(angle - 0.45), math.sin(angle - 0.45)) * size;
    final right =
        tip - Offset(math.cos(angle + 0.45), math.sin(angle + 0.45)) * size;

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawEdgeLabel(
    Canvas canvas,
    GraphEdgeModel edge,
    Path path,
    bool selected,
  ) {
    final metricsIterator = path.computeMetrics().iterator;
    if (!metricsIterator.moveNext()) {
      return;
    }

    final metric = metricsIterator.current;
    final tangent = metric.getTangentForOffset(metric.length * 0.5);
    if (tangent == null) {
      return;
    }

    final text = relationTypeLabel(edge.relationType);
    final span = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 10.5,
        color: selected ? const Color(0xFF0E4B6E) : const Color(0xFF445D78),
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
    );

    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: tangent.position,
        width: painter.width + 10,
        height: painter.height + 6,
      ),
      const Radius.circular(6),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = const Color(0xFFD3E0EE)
        ..style = PaintingStyle.stroke,
    );

    painter.paint(
      canvas,
      tangent.position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  Color _edgeColor(String relationType, {required bool selected}) {
    final base = switch (relationType) {
      'manager_to_worker' => const Color(0xFF1A7A71),
      'dependency' => const Color(0xFF2A628E),
      'peer' => const Color(0xFF734A86),
      'feedback' => const Color(0xFF9A5A24),
      _ => const Color(0xFF5B6D83),
    };
    if (selected) {
      return base.withValues(alpha: 0.95);
    }
    return base.withValues(alpha: 0.86);
  }

  @override
  bool shouldRepaint(covariant GraphCanvasPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.tempEdge != tempEdge;
  }
}

class MiniMapPainter extends CustomPainter {
  const MiniMapPainter({required this.nodes, required this.viewport});

  final List<GraphNodeModel> nodes;
  final Rect viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF7FBFF),
    );

    final scaleX = size.width / graphCanvasWidth;
    final scaleY = size.height / graphCanvasHeight;

    final nodePaint = Paint()..color = const Color(0xFF96B4D3);
    for (final node in nodes) {
      final rect = Rect.fromLTWH(
        node.x * scaleX,
        node.y * scaleY,
        graphNodeWidth * scaleX,
        graphNodeHeight * scaleY,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        nodePaint,
      );
    }

    final viewRect = Rect.fromLTWH(
      viewport.left * scaleX,
      viewport.top * scaleY,
      viewport.width * scaleX,
      viewport.height * scaleY,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(viewRect, const Radius.circular(4)),
      Paint()
        ..color = const Color(0x33247AB5)
        ..style = PaintingStyle.fill,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(viewRect, const Radius.circular(4)),
      Paint()
        ..color = const Color(0xFF247AB5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant MiniMapPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.viewport != viewport;
  }
}

