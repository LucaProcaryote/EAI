import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

/// Everything the engine has handled, with the full trace of each message.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  MessageStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return Column(
      children: <Widget>[
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.sm),
                child: FilterChip(
                  selected: _filter == null,
                  label: Text(l10n.labelAll),
                  onSelected: (_) => setState(() => _filter = null),
                ),
              ),
              for (final status in MessageStatus.values)
                Padding(
                  padding: const EdgeInsets.only(
                    left: Gap.sm,
                    top: Gap.sm,
                    bottom: Gap.sm,
                  ),
                  child: FilterChip(
                    selected: _filter == status,
                    label: Text(status.display.forLanguage(language)),
                    onSelected: (_) => setState(() => _filter = status),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RepositoryBuilder<List<IntegrationMessage>>(
            query: (repository) =>
                repository.listMessages(status: _filter, limit: 200),
            builder: (context, messages) {
              if (messages.isEmpty) {
                return EmptyView(
                  message: l10n.eaiNoMessages,
                  icon: Icons.forum_outlined,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(Gap.md),
                itemCount: messages.length,
                separatorBuilder: (_, __) => Gap.h8,
                itemBuilder: (context, index) =>
                    _MessageCard(message: messages[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final IntegrationMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    final color = switch (message.status) {
      MessageStatus.delivered => HospitalTheme.successOf(context),
      MessageStatus.failed => HospitalTheme.criticalOf(context),
      MessageStatus.filtered => HospitalTheme.warningOf(context),
      _ => HospitalTheme.infoOf(context),
    };

    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: Gap.md),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                message.messageType,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            StatusChip(
              label: message.status.display.forLanguage(language),
              color: color,
              dense: true,
            ),
          ],
        ),
        subtitle: Text(
          <String>[
            '${message.sourceApp}${message.targetApp == null ? '' : ' → ${message.targetApp}'}',
            Formats.smart(context, message.receivedAt),
            if (message.latency != null)
              '${l10n.eaiLatency} ${message.latency!.inMilliseconds} ms',
            if (message.patientId != null) message.patientId!,
          ].join(' · '),
          style: theme.textTheme.labelSmall,
        ),
        children: <Widget>[
          if (message.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: HospitalTheme.criticalOf(context),
                  ),
                  Gap.w8,
                  Expanded(
                    child: Text(
                      message.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: HospitalTheme.criticalOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (message.trace.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.eaiTrace, style: theme.textTheme.labelMedium),
                  Gap.h4,
                  for (var i = 0; i < message.trace.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('${i + 1}.', style: theme.textTheme.labelSmall),
                          Gap.w8,
                          Expanded(
                            child: Text(
                              '${message.trace[i].nodeLabel} — '
                              '${message.trace[i].detail}',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gap.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(message.payload),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
