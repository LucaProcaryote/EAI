import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import 'screens/flows_screen.dart';
import 'screens/fhir_screen.dart';
import 'screens/messages_screen.dart';
import 'services/engine_service.dart';

/// Navigation for the integration engine.
class EaiHome extends StatelessWidget {
  const EaiHome({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final config = context.read<AppConfig>();
    final repository = context.read<HospitalRepository>();

    return ChangeNotifierProvider<EngineService>(
      create: (_) => EngineService(
        repository: repository,
        fhir: FhirClient(baseUrl: config.fhirBaseUrl),
      ),
      child: AppShell(
        title: l10n.appTitleEai,
        destinations: <ShellDestination>[
          ShellDestination(
            label: (l10n) => l10n.eaiFlows,
            icon: Icons.account_tree_outlined,
            selectedIcon: Icons.account_tree,
            builder: (context) => const FlowsScreen(),
          ),
          ShellDestination(
            label: (l10n) => l10n.eaiMessages,
            icon: Icons.forum_outlined,
            selectedIcon: Icons.forum,
            builder: (context) => const MessagesScreen(),
          ),
          ShellDestination(
            label: (l10n) => l10n.eaiFhirResources,
            icon: Icons.storage_outlined,
            selectedIcon: Icons.storage,
            builder: (context) => const FhirScreen(),
          ),
        ],
      ),
    );
  }
}
