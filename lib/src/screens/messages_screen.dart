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
            child: _PayloadPanel(payload: message.payload),
          ),
        ],
      ),
    );
  }
}

/// The message body, as JSON and - when there is one - as the HL7 v2 text it
/// arrived in.
///
/// Showing only the parsed JSON would hide the thing worth seeing. A student
/// who has never met v2 needs to look at the pipes once to understand why
/// PID-5.1 is a position rather than a name, and why an unescaped `^` in a
/// surname is a data-loss bug rather than a cosmetic one.
class _PayloadPanel extends StatefulWidget {
  const _PayloadPanel({required this.payload});
  final Map<String, dynamic> payload;

  @override
  State<_PayloadPanel> createState() => _PayloadPanelState();
}

class _PayloadPanelState extends State<_PayloadPanel> {
  bool _showJson = false;

  String? get _hl7 {
    final raw = widget.payload['hl7'];
    return raw is String && raw.trim().isNotEmpty ? raw : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hl7 = _hl7;
    final showJson = hl7 == null || _showJson;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hl7 != null)
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('HL7 v2')),
                ButtonSegment<bool>(value: true, label: Text('JSON')),
              ],
              selected: <bool>{showJson},
              onSelectionChanged: (selection) =>
                  setState(() => _showJson = selection.first),
            ),
          ),
        if (hl7 != null) Gap.h8,
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Gap.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: showJson
              ? SelectableText(
                  const JsonEncoder.withIndent('  ').convert(widget.payload),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                )
              : _Er7View(message: hl7),
        ),
      ],
    );
  }
}

/// One segment per line, with its name set apart.
///
/// The wire format separates segments with a carriage return, which no text
/// widget renders as a line break - so the message would otherwise appear as
/// one unreadable ribbon.
class _Er7View extends StatelessWidget {
  const _Er7View({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = message
        .split(RegExp(r'\r\n|\r|\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 34,
                  child: Text(
                    line.length >= 3 ? line.substring(0, 3) : line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    line.length >= 3 ? line.substring(3) : '',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
