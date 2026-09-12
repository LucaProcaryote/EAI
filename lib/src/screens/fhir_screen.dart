import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/engine_service.dart';

/// The FHIR repository: is the server up, what is in it, and load the fictive
/// hospital into it.
class FhirScreen extends StatefulWidget {
  const FhirScreen({super.key});

  @override
  State<FhirScreen> createState() => _FhirScreenState();
}

class _FhirScreenState extends State<FhirScreen> {
  static const List<String> _resourceTypes = <String>[
    'Patient',
    'Encounter',
    'Observation',
    'MedicationRequest',
    'AllergyIntolerance',
    'Device',
  ];

  String _resourceType = 'Patient';
  final _searchController = TextEditingController();
  FhirBundle? _bundle;
  Object? _error;
  bool _loading = false;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EngineService>().checkFhirServer();
      _search();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final engine = context.read<EngineService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _searchController.text.trim();
      final bundle = await engine.fhir.search(
        _resourceType,
        parameters: query.isEmpty
            ? const <String, String>{}
            // `_content` is a full-text search across the resource, which is
            // the most forgiving thing to hand a student who does not yet know
            // the search parameters for each resource type.
            : <String, String>{'_content': query},
      );
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _seed() async {
    final engine = context.read<EngineService>();
    final l10n = HospitalLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _seeding = true);
    try {
      final count = await engine.seedFhirServer();
      messenger.showSnackBar(SnackBar(content: Text(l10n.eaiSeedDone(count))));
      await _search();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final theme = Theme.of(context);
    final engine = context.watch<EngineService>();
    final config = context.read<AppConfig>();
    final reachable = engine.fhirReachable;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  StatusChip(
                    label: reachable == null
                        ? l10n.labelLoading
                        : reachable
                            ? l10n.eaiServerOnline
                            : l10n.eaiServerOffline,
                    color: reachable == true
                        ? HospitalTheme.successOf(context)
                        : reachable == false
                            ? HospitalTheme.criticalOf(context)
                            : theme.colorScheme.outline,
                    icon: reachable == true ? Icons.cloud_done : Icons.cloud_off,
                  ),
                  Gap.w8,
                  Expanded(
                    child: Text(
                      config.fhirBaseUrl,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.actionRefresh,
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      engine.checkFhirServer();
                      _search();
                    },
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _seeding || reachable != true ? null : _seed,
                    icon: _seeding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload, size: 16),
                    label: Text(l10n.eaiSeedFhir),
                  ),
                ],
              ),
              if (reachable == false)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.sm),
                  child: Text(
                    // Say how to fix it rather than only that it is broken.
                    'docker compose up -d fhir   (see fhir-server/README.md)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: HospitalTheme.warningOf(context),
                    ),
                  ),
                ),
              Gap.h16,
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _resourceType,
                      decoration:
                          InputDecoration(labelText: l10n.eaiResourceType),
                      items: <DropdownMenuItem<String>>[
                        for (final type in _resourceTypes)
                          DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => _resourceType = value ?? _resourceType);
                        _search();
                      },
                    ),
                  ),
                  Gap.w16,
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: l10n.actionSearch,
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _results(context)),
      ],
    );
  }

  Widget _results(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(error: _error!, onRetry: _search);

    final bundle = _bundle;
    if (bundle == null || bundle.resources.isEmpty) {
      return EmptyView(
        message: l10n.eaiResourceCount(0),
        icon: Icons.storage_outlined,
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.eaiResourceCount(bundle.total),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
            itemCount: bundle.resources.length,
            separatorBuilder: (_, __) => Gap.h8,
            itemBuilder: (context, index) =>
                _ResourceCard(resource: bundle.resources[index]),
          ),
        ),
      ],
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.resource});

  final Map<String, dynamic> resource;

  /// A one-line human summary, so the list is scannable without expanding
  /// every entry into a wall of JSON.
  String _summarise() {
    switch (resource['resourceType']) {
      case 'Patient':
        final names = asMapList(resource['name']);
        if (names.isEmpty) return '';
        final given = asStringList(names.first['given']).join(' ');
        return '$given ${names.first['family'] ?? ''} · '
            '${resource['birthDate'] ?? ''}';
      case 'Observation':
        final codings = asMapList((resource['code'] as Map?)?['coding']);
        final display = codings.isEmpty ? '' : codings.first['display'] ?? '';
        final quantity = (resource['valueQuantity'] as Map?);
        return '$display · ${quantity?['value'] ?? ''} ${quantity?['unit'] ?? ''}';
      case 'Encounter':
        final period = (resource['period'] as Map?);
        return '${resource['status'] ?? ''} · ${period?['start'] ?? ''}';
      case 'MedicationRequest':
        final concept = resource['medicationCodeableConcept'] as Map?;
        return '${concept?['text'] ?? ''} · ${resource['status'] ?? ''}';
      default:
        return resource['status']?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: Gap.md),
        title: Text(
          '${resource['resourceType']}/${resource['id']}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(_summarise(), style: theme.textTheme.labelSmall),
        children: <Widget>[
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
                const JsonEncoder.withIndent('  ').convert(resource),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
