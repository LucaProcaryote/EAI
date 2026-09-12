import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';

import 'src/eai_home.dart';

/// Entry point of the interoperability server.
///
/// ```
/// flutter run -d chrome
/// flutter run -d chrome --dart-define=FHIR_BASE=http://localhost:8080/fhir
/// ```
void main() {
  runApp(
    MiniHospitalApp(
      config: AppConfig.fromEnvironment(HospitalApp.eai),
      title: (l10n) => l10n.appTitleEai,
      subtitle: (l10n) => l10n.hospitalName,
      homeBuilder: (context) => const EaiHome(),
    ),
  );
}
