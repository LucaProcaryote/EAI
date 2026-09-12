import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/flow_editor_controller.dart';

/// Geometry of a node box, shared by the canvas and the edge painter so the
/// wires land on the ports rather than near them.
class NodeMetrics {
  const NodeMetrics._();

  static const double width = 190;
  static const double height = 84;
  static const double portRadius = 7;

  static Offset inputPort(FlowNode node) =>
      Offset(node.x, node.y + height / 2);

  static Offset outputPort(FlowNode node) =>
      Offset(node.x + width, node.y + height / 2);
}

/// The drawing surface: nodes you can drag, ports you can wire together.
class FlowCanvas extends StatelessWidget {
  const FlowCanvas({super.key, this.canvasSize = const Size(2400, 1400)});

  final Size canvasSize;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FlowEditorController>();
    final theme = Theme.of(context);
    final flow = controller.flow;

    return DragTarget<FlowNodeType>(
      onAcceptWithDetails: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.offset);
        controller.addNode(
          details.data,
          local.dx.clamp(0, canvasSize.width - NodeMetrics.width),
          local.dy.clamp(0, canvasSize.height - NodeMetrics.height),
        );
      },
      builder: (context, candidate, rejected) => Container(
        color: theme.colorScheme.surfaceContainerLowest,
        child: InteractiveViewer(
          constrained: false,
          minScale: 0.4,
          maxScale: 2.0,
          boundaryMargin: const EdgeInsets.all(200),
          child: SizedBox(
            width: canvasSize.width,
            height: canvasSize.height,
            child: Stack(
              children: <Widget>[
                // The grid and the wires sit behind the nodes.
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CanvasPainter(
                      flow: flow,
                      gridColor: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.4),
                      edgeColor: theme.colorScheme.outline,
                      highlightColor: theme.colorScheme.primary,
                      connectingFrom: controller.connectingFromNodeId,
                    ),
                  ),
                ),
                // Tap a wire to delete it.
                for (final connection in flow.connections)
                  _ConnectionHandle(connection: connection, flow: flow),
                for (final node in flow.nodes)
                  _NodeBox(
                    node: node,
                    isSelected: node.id == controller.selectedNodeId,
                    isConnectingSource:
                        node.id == controller.connectingFromNodeId,
                  ),
                if (candidate.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: theme.colorScheme.primary.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter({
    required this.flow,
    required this.gridColor,
    required this.edgeColor,
    required this.highlightColor,
    required this.connectingFrom,
  });

  final IntegrationFlow flow;
  final Color gridColor;
  final Color edgeColor;
  final Color highlightColor;
  final String? connectingFrom;

  @override
  void paint(Canvas canvas, Size size) {
    // A light grid gives the eye something to align boxes against.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const spacing = 40.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (final connection in flow.connections) {
      final from = flow.nodeById(connection.fromNodeId);
      final to = flow.nodeById(connection.toNodeId);
      if (from == null || to == null) continue;

      final start = NodeMetrics.outputPort(from);
      final end = NodeMetrics.inputPort(to);
      final isHighlighted = connection.fromNodeId == connectingFrom;
      final paint = Paint()
        ..color = isHighlighted ? highlightColor : edgeColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawPath(_edgePath(start, end), paint);
      _drawArrowHead(canvas, end, paint..style = PaintingStyle.fill);

      // Routers have several outputs; say which one this wire leaves from.
      if (connection.fromPort != 'out') {
        _drawPortLabel(canvas, start, connection.fromPort);
      }
    }
  }

  /// A horizontal cubic keeps the wires readable when boxes are stacked, and
  /// avoids the tangle that straight lines produce on a dense canvas.
  static Path _edgePath(Offset start, Offset end) {
    final distance = (end.dx - start.dx).abs().clamp(60.0, 220.0);
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + distance * 0.6,
        start.dy,
        end.dx - distance * 0.6,
        end.dy,
        end.dx,
        end.dy,
      );
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Paint paint) {
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 9, tip.dy - 5)
      ..lineTo(tip.dx - 9, tip.dy + 5)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawPortLabel(Canvas canvas, Offset at, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(fontSize: 10, color: edgeColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(at.dx + 6, at.dy - painter.height - 2));
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.flow != flow || oldDelegate.connectingFrom != connectingFrom;
}

/// An invisible hit target sitting on the middle of a wire, so it can be
/// selected and deleted without needing pixel-perfect aim on the curve.
class _ConnectionHandle extends StatelessWidget {
  const _ConnectionHandle({required this.connection, required this.flow});

  final FlowConnection connection;
  final IntegrationFlow flow;

  @override
  Widget build(BuildContext context) {
    final from = flow.nodeById(connection.fromNodeId);
    final to = flow.nodeById(connection.toNodeId);
    if (from == null || to == null) return const SizedBox.shrink();

    final start = NodeMetrics.outputPort(from);
    final end = NodeMetrics.inputPort(to);
    final middle = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final l10n = HospitalLocalizations.of(context);

    return Positioned(
      left: middle.dx - 12,
      top: middle.dy - 12,
      child: Tooltip(
        message: l10n.eaiDisconnect,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              context.read<FlowEditorController>().deleteConnection(connection.id),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Icon(
              Icons.close,
              size: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeBox extends StatelessWidget {
  const _NodeBox({
    required this.node,
    required this.isSelected,
    required this.isConnectingSource,
  });

  final FlowNode node;
  final bool isSelected;
  final bool isConnectingSource;

  /// Sources, processors and destinations are coloured by family so the shape
  /// of a flow is readable at a glance; the family name is written on the box
  /// as well, so the colour is a shortcut and not the only signal.
  Color _familyColor(BuildContext context) => switch (node.type.family) {
        FlowNodeFamily.source => HospitalTheme.successOf(context),
        FlowNodeFamily.processor => HospitalTheme.infoOf(context),
        FlowNodeFamily.destination => HospitalTheme.warningOf(context),
      };

  IconData get _icon => switch (node.type) {
        FlowNodeType.httpSource => Icons.input,
        FlowNodeType.deviceSource => Icons.sensors,
        FlowNodeType.adtSource => Icons.swap_horiz,
        FlowNodeType.timerSource => Icons.schedule,
        FlowNodeType.filter => Icons.filter_alt_outlined,
        FlowNodeType.mapper => Icons.swap_calls,
        FlowNodeType.enricher => Icons.person_add_alt,
        FlowNodeType.validator => Icons.verified_outlined,
        FlowNodeType.codeTranslator => Icons.translate,
        FlowNodeType.router => Icons.call_split,
        FlowNodeType.fhirStore => Icons.storage,
        FlowNodeType.applicationDestination => Icons.apps,
        FlowNodeType.httpDestination => Icons.cloud_upload_outlined,
        FlowNodeType.logDestination => Icons.receipt_long,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.read<FlowEditorController>();
    final language = Localizations.localeOf(context).languageCode;
    final color = _familyColor(context);

    return Positioned(
      left: node.x,
      top: node.y,
      child: GestureDetector(
        onTap: () {
          if (controller.isConnecting) {
            final ok = controller.completeConnection(node.id);
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(HospitalLocalizations.of(context).errorGeneric),
                duration: const Duration(seconds: 2),
              ));
            }
          } else {
            controller.select(node.id);
          }
        },
        onPanStart: (_) => controller.beginDrag(),
        onPanUpdate: (details) => controller.moveNode(
          node.id,
          node.x + details.delta.dx,
          node.y + details.delta.dy,
        ),
        child: SizedBox(
          width: NodeMetrics.width,
          height: NodeMetrics.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                width: NodeMetrics.width,
                height: NodeMetrics.height,
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary : color,
                    width: isSelected ? 2.5 : 1.5,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(_icon, size: 14, color: color),
                        Gap.w4,
                        Expanded(
                          child: Text(
                            node.type.family.display.forLanguage(language),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: color),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Gap.h4,
                    Text(
                      node.label.isNotEmpty
                          ? node.label
                          : node.type.display.forLanguage(language),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      _summary(context),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (node.type.hasInput)
                Positioned(
                  left: -NodeMetrics.portRadius,
                  top: NodeMetrics.height / 2 - NodeMetrics.portRadius,
                  child: _Port(
                    color: color,
                    isTarget: true,
                    isActive: controller.isConnecting,
                    onTap: () => controller.completeConnection(node.id),
                  ),
                ),
              if (node.type.hasOutput)
                Positioned(
                  right: -NodeMetrics.portRadius,
                  top: NodeMetrics.height / 2 - NodeMetrics.portRadius,
                  child: _Port(
                    color: color,
                    isTarget: false,
                    isActive: isConnectingSource,
                    onTap: () => controller.isConnecting
                        ? controller.cancelConnection()
                        : controller.startConnection(node.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One line describing what the node is configured to do, so the canvas is
  /// readable without opening every properties panel.
  String _summary(BuildContext context) {
    final config = node.config;
    return switch (node.type) {
      FlowNodeType.filter =>
        '${config['path'] ?? '?'} ${FilterOperator.fromName((config['operator'] ?? 'equals').toString()).symbol} ${config['value'] ?? ''}',
      FlowNodeType.mapper =>
        '${(config['mappings'] as List?)?.length ?? 0} → ${HospitalLocalizations.of(context).eaiFieldMappings.toLowerCase()}',
      FlowNodeType.router =>
        '${config['path'] ?? '?'} · ${(config['routes'] as List?)?.length ?? 0}',
      FlowNodeType.applicationDestination => '${config['app'] ?? 'EHR'}',
      FlowNodeType.httpDestination =>
        (config['url'] as String?)?.isNotEmpty == true
            ? config['url'].toString()
            : '—',
      FlowNodeType.enricher => '${config['path'] ?? ''} → ${config['target'] ?? ''}',
      FlowNodeType.codeTranslator =>
        '${(config['table'] as Map?)?.length ?? 0} codes',
      _ => '',
    };
  }
}

class _Port extends StatelessWidget {
  const _Port({
    required this.color,
    required this.isTarget,
    required this.isActive,
    required this.onTap,
  });

  final Color color;
  final bool isTarget;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    return Tooltip(
      message: isTarget ? l10n.eaiPayloadBefore : l10n.eaiConnectHint,
      child: GestureDetector(
        onTap: onTap,
        // A 14px dot is too small to hit reliably, so pad the hit area out.
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: NodeMetrics.portRadius * 2,
            height: NodeMetrics.portRadius * 2,
            decoration: BoxDecoration(
              color: isActive ? Theme.of(context).colorScheme.primary : color,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
