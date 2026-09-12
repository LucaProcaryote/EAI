import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/engine_service.dart';
import '../services/flow_editor_controller.dart';

/// Runs a message through the flow being edited and shows what happened at
/// every step.
///
/// This is what makes the canvas teachable. A flow that only reports
/// "delivered" or "failed" tells a student nothing; seeing the payload change
/// shape as it passes the mapper, and seeing exactly which filter dropped it,
/// tells them everything.
class FlowTestPanel extends StatefulWidget {
  const FlowTestPanel({super.key});

  @override
  State<FlowTestPanel> createState() => _FlowTestPanelState();
}

class _FlowTestPanelState extends State<FlowTestPanel> {
  late final TextEditingController _payloadController = TextEditingController(
    text: _samples.values.first,
  );

  IntegrationMessage? _result;
  String? _error;
  bool _running = false;

  /// Ready-made payloads, so a student can test a flow before they know how to
  /// hand-write FHIR.
  static final Map<String, String> _samples = <String, String>{
    'Observation · SpO2 88%': const JsonEncoder.withIndent('  ').convert(
      <String, dynamic>{
        'resourceType': 'Observation',
        'id': 'obs-demo-1',
        'status': 'final',
        'code': <String, dynamic>{
          'coding': <dynamic>[
            <String, dynamic>{
              'system': 'http://loinc.org',
              'code': '2708-6',
              'display': 'Oxygen saturation',
            },
          ],
        },
        'subject': <String, dynamic>{'reference': 'Patient/pat-001'},
        'effectiveDateTime': '2026-09-12T10:00:00Z',
        'valueQuantity': <String, dynamic>{
          'value': 88,
          'unit': '%',
          'system': 'http://unitsofmeasure.org',
          'code': '%',
        },
        'device': <String, dynamic>{'reference': 'Device/DEV3'},
      },
    ),
    'Observation · heart rate 76': const JsonEncoder.withIndent('  ').convert(
      <String, dynamic>{
        'resourceType': 'Observation',
        'id': 'obs-demo-2',
        'status': 'final',
        'code': <String, dynamic>{
          'coding': <dynamic>[
            <String, dynamic>{
              'system': 'http://loinc.org',
              'code': '8867-4',
              'display': 'Heart rate',
            },
          ],
        },
        'subject': <String, dynamic>{'reference': 'Patient/pat-002'},
        'effectiveDateTime': '2026-09-12T10:00:00Z',
        'valueQuantity': <String, dynamic>{'value': 76, 'unit': 'bpm'},
      },
    ),
    'ADT · admission': const JsonEncoder.withIndent('  ')
        .convert(<String, dynamic>{
          'type': 'admission',
          'patient_id': 'pat-007',
          'to_ward_id': 'ward-int',
          'to_bed_id': 'bed-int-405a',
          'occurred_at': '2026-09-12T10:00:00Z',
          'performed_by': 'Fatima El Amrani',
        }),
    'ADT · discharge': const JsonEncoder.withIndent('  ')
        .convert(<String, dynamic>{
          'type': 'discharge',
          'patient_id': 'pat-003',
          'from_ward_id': 'ward-surg',
          'occurred_at': '2026-09-12T10:00:00Z',
          'performed_by': 'Fatima El Amrani',
        }),
    'Broken · not FHIR': const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, dynamic>{'temperature': 37.4, 'patient': 'Van Damme'}),
  };

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final l10n = HospitalLocalizations.of(context);
    final engine = context.read<EngineService>();
    final flow = context.read<FlowEditorController>().flow;

    setState(() {
      _error = null;
      _running = true;
      _result = null;
    });

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(_payloadController.text);
      if (decoded is! Map) throw const FormatException();
      payload = decoded.cast<String, dynamic>();
    } catch (_) {
      setState(() {
        _error = l10n.eaiInvalidJson;
        _running = false;
      });
      return;
    }

    // Always a dry run: pressing Test on a half-built flow must not write to
    // the FHIR server or the applications.
    final result = await engine.run(
      flow,
      engine.messageFrom(payload),
      dryRun: true,
    );

    if (!mounted) return;
    setState(() {
      _result = result;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 320,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l10n.eaiTestPayload,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: l10n.eaiSamplePayload,
                      icon: const Icon(Icons.folder_open, size: 18),
                      onSelected: (key) => setState(() {
                        _payloadController.text = _samples[key]!;
                        _error = null;
                      }),
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        for (final key in _samples.keys)
                          PopupMenuItem<String>(value: key, child: Text(key)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                  child: TextField(
                    controller: _payloadController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                    decoration: InputDecoration(errorText: _error),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(l10n.eaiRunTest),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _TraceView(result: _result)),
      ],
    );
  }
}

class _TraceView extends StatelessWidget {
  const _TraceView({required this.result});

  final IntegrationMessage? result;

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final message = result;

    if (message == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Gap.lg),
          child: Text(
            l10n.eaiTraceEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final overallColor = switch (message.status) {
      MessageStatus.delivered => HospitalTheme.successOf(context),
      MessageStatus.failed => HospitalTheme.criticalOf(context),
      MessageStatus.filtered => HospitalTheme.warningOf(context),
      _ => theme.colorScheme.outline,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            children: <Widget>[
              Text(l10n.eaiTrace, style: theme.textTheme.labelLarge),
              Gap.w8,
              StatusChip(
                label: message.status.display.forLanguage(language),
                color: overallColor,
                dense: true,
              ),
              if (message.error != null) ...<Widget>[
                Gap.w8,
                Expanded(
                  child: Text(
                    message.error!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: HospitalTheme.criticalOf(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(Gap.md),
            itemCount: message.trace.length,
            itemBuilder: (context, index) =>
                _TraceStepTile(step: message.trace[index], index: index),
          ),
        ),
      ],
    );
  }
}

class _TraceStepTile extends StatelessWidget {
  const _TraceStepTile({required this.step, required this.index});

  final TraceStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = HospitalLocalizations.of(context);

    final (Color color, String label) = switch (step.status) {
      MessageStatus.delivered => (
        HospitalTheme.successOf(context),
        l10n.eaiStepPassed,
      ),
      MessageStatus.failed => (
        HospitalTheme.criticalOf(context),
        l10n.eaiStepFailed,
      ),
      MessageStatus.filtered => (
        HospitalTheme.warningOf(context),
        l10n.eaiStepDropped,
      ),
      _ => (HospitalTheme.infoOf(context), l10n.eaiStepPassed),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: Gap.md),
        leading: CircleAvatar(
          radius: 13,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(
            '${index + 1}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                step.nodeLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StatusChip(label: label, color: color, dense: true),
          ],
        ),
        subtitle: Text(step.detail, style: theme.textTheme.labelSmall),
        children: <Widget>[
          if (step.payloadAfter != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
              padding: const EdgeInsets.all(Gap.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(step.payloadAfter),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
