// ignore_for_file: deprecated_member_use
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/graph_editor_models.dart';
import '../state/graph_editor_controller.dart';
import 'graph_ui_models.dart';
import 'make_tokens.dart';

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
      ..translate(180.0, 120.0)
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
        // During relayout viewer can be unavailable for one frame.
      }
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
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
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(MakeTokens.radiusLg),
                      border: Border.all(
                        color: isDropHover
                            ? MakeTokens.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
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
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: MakeTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MakeTokens.border),
        boxShadow: MakeTokens.softShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onTap: () => _zoomBy(0.9),
          ),
          _toolButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onTap: () => _zoomBy(1.1),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MakeTokens.border),
            ),
            child: Text(
              '${(scale * 100).round()}%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MakeTokens.muted,
              ),
            ),
          ),
          _toolButton(
            icon: Icons.center_focus_strong,
            tooltip: 'Reset view',
            onTap: _resetView,
          ),
        ],
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: MakeTokens.border),
              color: Colors.white.withValues(alpha: 0.9),
            ),
            child: Icon(icon, size: 16, color: MakeTokens.text),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniMap(Size viewportSize) {
    final sceneViewport = _sceneViewportRect(viewportSize);
    return Container(
      width: 180,
      height: 118,
      decoration: BoxDecoration(
        color: MakeTokens.surfaceStrong,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MakeTokens.border),
        boxShadow: MakeTokens.softShadow,
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
        nodePanEnabled: _connectingFromNodeId == null,
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

    final start = _outputAnchorForNode(fromNode);

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
      ..translate(180.0, 120.0)
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

    throw StateError('Canvas RenderBox is unavailable.');
  }

  Offset _globalToScene(Offset globalPosition) {
    final box = _viewerBox();
    final local = box.globalToLocal(globalPosition);
    return _transformationController.toScene(local);
  }

  GraphEdgeModel? _findEdgeNearPoint(Offset scenePoint) {
    const hitDistance = 10.0;

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

      final start = Offset(from.x + (graphNodeWidth / 2), from.y + 104);
      final end = Offset(to.x + (graphNodeWidth / 2), to.y + 20);
      final c1 = Offset(start.dx, start.dy - 90);
      final c2 = Offset(end.dx, end.dy + 90);
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
      final bounds = Rect.fromLTWH(node.x, node.y, graphNodeWidth, graphNodeHeight);
      if (bounds.inflate(12).contains(scenePoint)) {
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
    const steps = 30;

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

  Offset _outputAnchorForNode(GraphNodeModel node) {
    return Offset(node.x + (graphNodeWidth / 2), node.y + 104);
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
    required this.nodePanEnabled,
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
  final bool nodePanEnabled;

  @override
  Widget build(BuildContext context) {
    final roleStyle = MakeTokens.rolePalette(node.config.role);
    final statusStyle = MakeTokens.statusPalette(status);

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onPanStart: nodePanEnabled ? (_) => onPanStart() : null,
      onPanUpdate: nodePanEnabled ? (details) => onPanUpdate(details.delta) : null,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 12,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.88),
                border: Border.all(
                  color: selected ? roleStyle.ring : MakeTokens.border,
                  width: selected ? 2.0 : 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1C1A2D4E),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: roleStyle.bg,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      node.config.role,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MakeTokens.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      node.config.agentId,
                      style: const TextStyle(
                        fontSize: 10,
                        color: MakeTokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(top: 8, child: _statusDot(statusStyle.fg)),
          Positioned(
            top: 98,
            child: GestureDetector(
              onPanStart: (details) =>
                  onOutputConnectStart(details.globalPosition),
              onPanUpdate: (details) =>
                  onOutputConnectUpdate(details.globalPosition),
              onPanEnd: (_) => onOutputConnectEnd(),
              onPanCancel: onOutputConnectCancel,
              child: _portDot(const Color(0xFF14B87A)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 108,
            child: Column(
              children: [
                Text(
                  node.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: MakeTokens.text,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusStyle.border),
                    color: statusStyle.bg,
                  ),
                  child: Text(
                    nodeExecutionStatusLabel(status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusStyle.fg,
                    ),
                  ),
                ),
                if ((errorText ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      errorText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        color: MakeTokens.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _portDot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.6),
      ),
    );
  }
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
    final major = Paint()
      ..color = const Color(0x19708EB8)
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = const Color(0x116E8AB3)
      ..strokeWidth = 1;

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

      final start = Offset(from.x + (graphNodeWidth / 2), from.y + 104);
      final end = Offset(to.x + (graphNodeWidth / 2), to.y + 20);

      final c1 = Offset(start.dx, start.dy - 80);
      final c2 = Offset(end.dx, end.dy + 80);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

      final isSelected = edge.id == selectedEdgeId;
      final color = MakeTokens.edgeColor(
        edge.relationType,
      ).withValues(alpha: isSelected ? 0.95 : 0.8);

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.0 : 2.0;

      canvas.drawPath(path, paint);
      _drawArrow(canvas, end, c2, color, isSelected ? 8 : 7);
      _drawEdgeLabel(canvas, edge, path, color, isSelected);
    }
  }

  void _paintTempEdge(Canvas canvas, TempEdge edge) {
    final color = MakeTokens.edgeColor(edge.relationType);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final c1 = Offset(edge.from.dx, edge.from.dy - 70);
    final c2 = Offset(edge.to.dx, edge.to.dy + 70);

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
    Color color,
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

    final text = edge.relationType;
    final span = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 10,
        color: selected ? color : const Color(0xFF455D7D),
        fontWeight: FontWeight.w600,
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
        width: painter.width + 12,
        height: painter.height + 6,
      ),
      const Radius.circular(7),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = MakeTokens.border
        ..style = PaintingStyle.stroke,
    );

    painter.paint(
      canvas,
      tangent.position - Offset(painter.width / 2, painter.height / 2),
    );
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

    final nodePaint = Paint()..color = const Color(0x885D89C5);
    for (final node in nodes) {
      final center = Offset(
        (node.x + (graphNodeWidth / 2)) * scaleX,
        (node.y + 44) * scaleY,
      );
      canvas.drawCircle(center, 4, nodePaint);
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
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant MiniMapPainter oldDelegate) {
    return oldDelegate.nodes != nodes || oldDelegate.viewport != viewport;
  }
}
