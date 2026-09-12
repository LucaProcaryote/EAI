import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/engine_service.dart';
import 'flow_editor_screen.dart';

/// The list of integration flows.
class FlowsScreen extends StatelessWidget {
  const FlowsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final canEdit = context
            .watch<AuthService>()
            .currentUser
            ?.role
            .canConfigureIntegration ??
        false;

    return Stack(
      children: <Widget>[
        RepositoryBuilder<List<IntegrationFlow>>(
          query: (repository) => repository.listFlows(),
          builder: (context, flows) {
            if (flows.isEmpty) {
              return EmptyView(
                message: l10n.labelNoResults,
                icon: Icons.account_tree_outlined,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 88),
              itemCount: flows.length,
              separatorBuilder: (_, __) => Gap.h8,
              itemBuilder: (context, index) =>
                  _FlowCard(flow: flows[index], canEdit: canEdit),
            );
          },
        ),
        if (canEdit)
          Positioned(
            right: Gap.md,
            bottom: Gap.md,
            child: FloatingActionButton.extended(
              onPressed: () => _newFlow(context),
              icon: const Icon(Icons.add),
              label: Text(l10n.eaiNewFlow),
            ),
          ),
      ],
    );
  }

  Future<void> _newFlow(BuildContext context) async {
    final repository = context.read<HospitalRepository>();
    final engine = context.read<EngineService>();
    final navigator = Navigator.of(context);

    final flow = IntegrationFlow(
      id: 'flow-${const Uuid().v4().substring(0, 8)}',
      name: const LocalizedText(
        en: 'New flow',
        fr: 'Nouveau flux',
        nl: 'Nieuwe stroom',
      ),
      description: const LocalizedText.same(''),
      isEnabled: false,
      nodes: const <FlowNode>[],
      connections: const <FlowConnection>[],
      updatedAt: DateTime.now(),
    );
    final saved = await repository.saveFlow(flow);

    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<EngineService>.value(
        value: engine,
        child: FlowEditorScreen(flow: saved),
      ),
    ));
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.flow, required this.canEdit});

  final IntegrationFlow flow;
  final bool canEdit;

  /// The editor is a pushed route, so it builds on the root navigator - above
  /// the provider EaiHome installs. The engine has to be handed down
  /// explicitly or the test panel cannot find it.
  void _open(BuildContext context) {
    final engine = context.read<EngineService>();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<EngineService>.value(
        value: engine,
        child: FlowEditorScreen(flow: flow),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final issues = flow.validate();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: canEdit ? () => _open(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      flow.name.forLanguage(language),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  StatusChip(
                    label: flow.isEnabled ? l10n.eaiEnabled : l10n.eaiDisabled,
                    color: flow.isEnabled
                        ? HospitalTheme.successOf(context)
                        : theme.colorScheme.outline,
                    icon: flow.isEnabled ? Icons.play_arrow : Icons.pause,
                    dense: true,
                  ),
                ],
              ),
              Gap.h8,
              Text(
                flow.description.forLanguage(language),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Gap.h16,
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: <Widget>[
                  StatusChip(
                    label: '${flow.nodes.length} ${l10n.eaiPalette.toLowerCase()}',
                    color: HospitalTheme.infoOf(context),
                    icon: Icons.widgets_outlined,
                    dense: true,
                  ),
                  StatusChip(
                    label: '${flow.messagesProcessed} ${l10n.eaiMessages.toLowerCase()}',
                    color: theme.colorScheme.outline,
                    icon: Icons.forum_outlined,
                    dense: true,
                  ),
                  if (flow.messagesFailed > 0)
                    StatusChip(
                      label: '${flow.messagesFailed}',
                      color: HospitalTheme.criticalOf(context),
                      icon: Icons.error_outline,
                      dense: true,
                    ),
                  if (issues.isNotEmpty)
                    StatusChip(
                      label: l10n.eaiValidationIssues(issues.length),
                      color: HospitalTheme.warningOf(context),
                      icon: Icons.warning_amber_rounded,
                      dense: true,
                    ),
                ],
              ),
              Gap.h8,
              Text(
                '${l10n.labelDate}: ${Formats.dateTime(context, flow.updatedAt)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
