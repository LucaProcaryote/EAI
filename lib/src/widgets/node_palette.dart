import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

import 'flow_canvas.dart';

/// The building blocks, grouped by family, ready to be dragged onto the canvas.
class NodePalette extends StatelessWidget {
  const NodePalette({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.eaiPalette,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Gap.h4,
              Text(
                l10n.eaiDragHint,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: Gap.sm),
            children: <Widget>[
              for (final family in FlowNodeFamily.values) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.xs),
                  child: Text(
                    family.display.forLanguage(language),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final type
                    in FlowNodeType.values.where((t) => t.family == family))
                  _PaletteItem(type: type),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PaletteItem extends StatelessWidget {
  const _PaletteItem({required this.type});

  final FlowNodeType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final color = switch (type.family) {
      FlowNodeFamily.source => HospitalTheme.successOf(context),
      FlowNodeFamily.processor => HospitalTheme.infoOf(context),
      FlowNodeFamily.destination => HospitalTheme.warningOf(context),
    };

    final tile = Container(
      margin: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.sm,
        vertical: Gap.sm - 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.drag_indicator, size: 14, color: color),
          Gap.w8,
          Expanded(
            child: Text(
              type.display.forLanguage(language),
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: type.description.forLanguage(language),
      waitDuration: const Duration(milliseconds: 400),
      child: Draggable<FlowNodeType>(
        data: type,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.9,
            child: SizedBox(
              width: NodeMetrics.width,
              child: Container(
                padding: const EdgeInsets.all(Gap.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color, width: 2),
                ),
                child: Text(
                  type.display.forLanguage(language),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: tile),
        child: tile,
      ),
    );
  }
}
