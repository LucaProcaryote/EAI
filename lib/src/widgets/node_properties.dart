import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/flow_editor_controller.dart';

/// The properties panel for the selected node.
///
/// Each node type gets an editor shaped like its configuration, rather than a
/// raw JSON box: the students are learning what a field mapper *is*, and a text
/// area full of braces teaches them nothing about that.
class NodeProperties extends StatelessWidget {
  const NodeProperties({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FlowEditorController>();
    final l10n = HospitalLocalizations.of(context);
    final theme = Theme.of(context);
    final node = controller.selectedNode;

    if (node == null) {
      return Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.eaiProperties,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Gap.h16,
            Text(
              l10n.eaiSelectNode,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Gap.h24,
            const _ValidationList(),
          ],
        ),
      );
    }

    final language = Localizations.localeOf(context).languageCode;

    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                node.type.display.forLanguage(language),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: l10n.eaiDeleteNode,
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => controller.deleteNode(node.id),
            ),
          ],
        ),
        Text(
          node.type.description.forLanguage(language),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Gap.h16,
        TextFormField(
          key: ValueKey<String>('label-${node.id}'),
          initialValue: node.label,
          decoration: InputDecoration(labelText: l10n.eaiNodeLabel),
          onChanged: (value) => controller.setNodeLabel(node.id, value),
        ),
        Gap.h16,
        ..._editorFor(context, controller, node),
        Gap.h24,
        const _ValidationList(),
      ],
    );
  }

  List<Widget> _editorFor(
    BuildContext context,
    FlowEditorController controller,
    FlowNode node,
  ) =>
      switch (node.type) {
        FlowNodeType.filter => <Widget>[_FilterEditor(node: node)],
        FlowNodeType.mapper => <Widget>[_MapperEditor(node: node)],
        FlowNodeType.enricher => <Widget>[_EnricherEditor(node: node)],
        FlowNodeType.router => <Widget>[_RouterEditor(node: node)],
        FlowNodeType.applicationDestination => <Widget>[
            _ApplicationEditor(node: node),
          ],
        FlowNodeType.httpDestination => <Widget>[_HttpEditor(node: node)],
        FlowNodeType.codeTranslator => <Widget>[_TranslatorEditor(node: node)],
        _ => <Widget>[],
      };
}

/// Live list of everything that would stop the flow from running.
class _ValidationList extends StatelessWidget {
  const _ValidationList();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FlowEditorController>();
    final l10n = HospitalLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final issues = controller.issues;

    if (issues.isEmpty) {
      return Row(
        children: <Widget>[
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: HospitalTheme.successOf(context),
          ),
          Gap.w8,
          Expanded(
            child: Text(l10n.eaiFlowValid, style: theme.textTheme.bodySmall),
          ),
        ],
      );
    }

    final color = HospitalTheme.warningOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.eaiValidationIssues(issues.length),
          style: theme.textTheme.labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        Gap.h8,
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.xs),
            child: InkWell(
              onTap: issue.nodeId == null
                  ? null
                  : () => controller.select(issue.nodeId),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, size: 14, color: color),
                  Gap.w8,
                  Expanded(
                    child: Text(
                      issue.message.forLanguage(language),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Per-type editors
// ---------------------------------------------------------------------------

class _FilterEditor extends StatelessWidget {
  const _FilterEditor({required this.node});
  final FlowNode node;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final controller = context.read<FlowEditorController>();
    final operator = FilterOperator.fromName(
      (node.config['operator'] ?? 'equals').toString(),
    );

    void update(String key, Object? value) => controller.setNodeConfig(
          node.id,
          <String, dynamic>{...node.config, key: value},
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          key: ValueKey<String>('path-${node.id}'),
          initialValue: (node.config['path'] ?? '').toString(),
          decoration: InputDecoration(
            labelText: l10n.eaiFieldPath,
            hintText: 'valueQuantity.value',
          ),
          onChanged: (value) => update('path', value),
        ),
        Gap.h16,
        DropdownButtonFormField<FilterOperator>(
          initialValue: operator,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.eaiOperator),
          items: <DropdownMenuItem<FilterOperator>>[
            for (final option in FilterOperator.values)
              DropdownMenuItem<FilterOperator>(
                value: option,
                child: Text(
                  '${option.symbol}  ${option.display.forLanguage(language)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => update('operator', value?.name),
        ),
        if (operator.takesValue) ...<Widget>[
          Gap.h16,
          TextFormField(
            key: ValueKey<String>('value-${node.id}'),
            initialValue: (node.config['value'] ?? '').toString(),
            decoration: InputDecoration(labelText: l10n.eaiTransformArgument),
            onChanged: (value) => update('value', value),
          ),
        ],
      ],
    );
  }
}

class _MapperEditor extends StatelessWidget {
  const _MapperEditor({required this.node});
  final FlowNode node;

  List<FieldMapping> get _mappings =>
      (node.config['mappings'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => FieldMapping.fromJson(m.cast<String, dynamic>()))
          .toList();

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final controller = context.read<FlowEditorController>();
    final mappings = _mappings;

    void save(List<FieldMapping> next) => controller.setNodeConfig(
          node.id,
          <String, dynamic>{
            ...node.config,
            'mappings': next.map((m) => m.toJson()).toList(),
          },
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile(
          value: node.config['keepUnmapped'] == true,
          onChanged: (value) => controller.setNodeConfig(
            node.id,
            <String, dynamic>{...node.config, 'keepUnmapped': value},
          ),
          title: Text(
            l10n.eaiKeepUnmapped,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const Divider(),
        for (var i = 0; i < mappings.length; i++)
          _MappingRow(
            key: ValueKey<String>('${node.id}-map-$i'),
            mapping: mappings[i],
            language: language,
            onChanged: (updated) {
              final next = List<FieldMapping>.of(mappings);
              next[i] = updated;
              save(next);
            },
            onRemove: () {
              final next = List<FieldMapping>.of(mappings)..removeAt(i);
              save(next);
            },
          ),
        Gap.h8,
        OutlinedButton.icon(
          onPressed: () => save(<FieldMapping>[
            ...mappings,
            const FieldMapping(sourcePath: '', targetPath: ''),
          ]),
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.eaiAddMapping),
        ),
      ],
    );
  }
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    super.key,
    required this.mapping,
    required this.language,
    required this.onChanged,
    required this.onRemove,
  });

  final FieldMapping mapping;
  final String language;
  final ValueChanged<FieldMapping> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  initialValue: mapping.sourcePath,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: l10n.eaiSourceField,
                    isDense: true,
                  ),
                  onChanged: (value) => onChanged(FieldMapping(
                    sourcePath: value,
                    targetPath: mapping.targetPath,
                    transform: mapping.transform,
                    argument: mapping.argument,
                  )),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 14),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: mapping.targetPath,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    labelText: l10n.eaiTargetField,
                    isDense: true,
                  ),
                  onChanged: (value) => onChanged(FieldMapping(
                    sourcePath: mapping.sourcePath,
                    targetPath: value,
                    transform: mapping.transform,
                    argument: mapping.argument,
                  )),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Gap.h4,
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<FieldTransform>(
                  initialValue: mapping.transform,
                  isDense: true,
                  isExpanded: true,
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: InputDecoration(
                    labelText: l10n.eaiTransform,
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<FieldTransform>>[
                    for (final transform in FieldTransform.values)
                      DropdownMenuItem<FieldTransform>(
                        value: transform,
                        child: Text(
                          transform.display.forLanguage(language),
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => onChanged(FieldMapping(
                    sourcePath: mapping.sourcePath,
                    targetPath: mapping.targetPath,
                    transform: value ?? FieldTransform.none,
                    argument: mapping.argument,
                  )),
                ),
              ),
              if (mapping.transform.takesArgument) ...<Widget>[
                Gap.w8,
                Expanded(
                  child: TextFormField(
                    initialValue: mapping.argument ?? '',
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: l10n.eaiTransformArgument,
                      isDense: true,
                    ),
                    onChanged: (value) => onChanged(FieldMapping(
                      sourcePath: mapping.sourcePath,
                      targetPath: mapping.targetPath,
                      transform: mapping.transform,
                      argument: value,
                    )),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EnricherEditor extends StatelessWidget {
  const _EnricherEditor({required this.node});
  final FlowNode node;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final controller = context.read<FlowEditorController>();

    void update(String key, String value) => controller.setNodeConfig(
          node.id,
          <String, dynamic>{...node.config, key: value},
        );

    return Column(
      children: <Widget>[
        TextFormField(
          key: ValueKey<String>('epath-${node.id}'),
          initialValue: (node.config['path'] ?? '').toString(),
          decoration: InputDecoration(
            labelText: l10n.eaiSourceField,
            hintText: 'subject.reference',
          ),
          onChanged: (value) => update('path', value),
        ),
        Gap.h16,
        TextFormField(
          key: ValueKey<String>('etarget-${node.id}'),
          initialValue: (node.config['target'] ?? '').toString(),
          decoration: InputDecoration(
            labelText: l10n.eaiTargetField,
            hintText: 'patient',
          ),
          onChanged: (value) => update('target', value),
        ),
      ],
    );
  }
}

class _RouterEditor extends StatelessWidget {
  const _RouterEditor({required this.node});
  final FlowNode node;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final controller = context.read<FlowEditorController>();
    final routes = (node.config['routes'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((r) => r.cast<String, dynamic>())
        .toList();

    void save(List<Map<String, dynamic>> next) => controller.setNodeConfig(
          node.id,
          <String, dynamic>{...node.config, 'routes': next},
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          key: ValueKey<String>('rpath-${node.id}'),
          initialValue: (node.config['path'] ?? '').toString(),
          decoration: InputDecoration(
            labelText: l10n.eaiFieldPath,
            hintText: 'type',
          ),
          onChanged: (value) => controller.setNodeConfig(
            node.id,
            <String, dynamic>{...node.config, 'path': value},
          ),
        ),
        Gap.h16,
        Text(l10n.eaiRoutes, style: Theme.of(context).textTheme.labelMedium),
        Gap.h8,
        for (var i = 0; i < routes.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>('${node.id}-rv-$i'),
                    initialValue: (routes[i]['value'] ?? '').toString(),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: l10n.eaiTransformArgument,
                      isDense: true,
                    ),
                    onChanged: (value) {
                      final next = List<Map<String, dynamic>>.of(routes);
                      next[i] = <String, dynamic>{...next[i], 'value': value};
                      save(next);
                    },
                  ),
                ),
                Gap.w8,
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>('${node.id}-rp-$i'),
                    initialValue: (routes[i]['port'] ?? '').toString(),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'port',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      final next = List<Map<String, dynamic>>.of(routes);
                      next[i] = <String, dynamic>{...next[i], 'port': value};
                      save(next);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      save(List<Map<String, dynamic>>.of(routes)..removeAt(i)),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => save(<Map<String, dynamic>>[
            ...routes,
            <String, dynamic>{'value': '', 'port': 'out${routes.length + 1}'},
          ]),
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.actionAdd),
        ),
      ],
    );
  }
}

class _ApplicationEditor extends StatelessWidget {
  const _ApplicationEditor({required this.node});
  final FlowNode node;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<FlowEditorController>();
    return DropdownButtonFormField<String>(
      initialValue: (node.config['app'] ?? 'EHR').toString(),
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Application'),
      items: const <DropdownMenuItem<String>>[
        DropdownMenuItem<String>(value: 'EHR', child: Text('EHR')),
        DropdownMenuItem<String>(value: 'ADT', child: Text('ADT')),
        DropdownMenuItem<String>(value: 'PHARM', child: Text('PHARM')),
      ],
      onChanged: (value) => controller.setNodeConfig(
        node.id,
        <String, dynamic>{...node.config, 'app': value},
      ),
    );
  }
}

class _HttpEditor extends StatelessWidget {
  const _HttpEditor({required this.node});
  final FlowNode node;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<FlowEditorController>();
    return Column(
      children: <Widget>[
        TextFormField(
          key: ValueKey<String>('url-${node.id}'),
          initialValue: (node.config['url'] ?? '').toString(),
          decoration: const InputDecoration(
            labelText: 'URL',
            hintText: 'https://example.org/inbox',
          ),
          onChanged: (value) => controller.setNodeConfig(
            node.id,
            <String, dynamic>{...node.config, 'url': value},
          ),
        ),
        Gap.h8,
        Text(
          // Say this here rather than letting a student discover it as a
          // runtime failure.
          'Outbound HTTP is disabled in the classroom build.',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: HospitalTheme.warningOf(context),
              ),
        ),
      ],
    );
  }
}

class _TranslatorEditor extends StatelessWidget {
  const _TranslatorEditor({required this.node});
  final FlowNode node;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final controller = context.read<FlowEditorController>();
    final table = (node.config['table'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final entries = table.entries.toList();

    void save(Map<String, dynamic> next) => controller.setNodeConfig(
          node.id,
          <String, dynamic>{...node.config, 'table': next},
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          key: ValueKey<String>('tpath-${node.id}'),
          initialValue: (node.config['path'] ?? '').toString(),
          decoration: InputDecoration(labelText: l10n.eaiFieldPath),
          onChanged: (value) => controller.setNodeConfig(
            node.id,
            <String, dynamic>{...node.config, 'path': value},
          ),
        ),
        Gap.h16,
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>('${node.id}-tk-$i'),
                    initialValue: entries[i].key,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'from',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      final next = <String, dynamic>{...table};
                      next.remove(entries[i].key);
                      next[value] = entries[i].value;
                      save(next);
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.arrow_forward, size: 14),
                ),
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>('${node.id}-tv-$i'),
                    initialValue: entries[i].value.toString(),
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'to',
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        save(<String, dynamic>{...table, entries[i].key: value}),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final next = <String, dynamic>{...table}
                      ..remove(entries[i].key);
                    save(next);
                  },
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => save(<String, dynamic>{...table, '': ''}),
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.actionAdd),
        ),
      ],
    );
  }
}
