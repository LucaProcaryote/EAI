import 'package:eai_app/src/eai_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_core/hospital_core.dart';

Future<void> pumpEai(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  final repository = MemoryHospitalRepository(
    seed: HospitalSeed.build(now: DateTime.utc(2026, 9, 12, 10)),
  );
  final auth = DemoAuthService();
  await auth.initialize();
  await auth.signInAs(
    seedUsers.firstWhere((u) => u.role == UserRole.integrationEngineer),
  );

  await tester.pumpWidget(
    MiniHospitalApp(
      config: const AppConfig(
        app: HospitalApp.eai,
        backendMode: BackendMode.memory,
        authMode: AuthMode.demo,
        apiBaseUrl: '',
        // Unroutable, so the FHIR status check fails fast rather than hanging.
        fhirBaseUrl: 'http://127.0.0.1:1/fhir',
        eaiBaseUrl: '',
      ),
      title: (l10n) => l10n.appTitleEai,
      homeBuilder: (context) => const EaiHome(),
      repositoryOverride: repository,
      authOverride: auth,
      localeStore: InMemoryLocaleStore(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the flow list shows the worked examples', (tester) async {
    await pumpEai(tester);

    expect(find.text('Interoperability Server'), findsOneWidget);
    expect(find.text('Device vitals to the record'), findsOneWidget);
    expect(find.text('ADT movements fan-out'), findsOneWidget);
    expect(find.text('Low SpO2 alert'), findsOneWidget);
    // The seeded flows are all structurally sound, so none is flagged.
    expect(find.textContaining('problem to fix'), findsNothing);
  });

  testWidgets('opening a flow shows palette, canvas and properties', (
    tester,
  ) async {
    await pumpEai(tester);

    await tester.tap(find.text('Low SpO2 alert'));
    await tester.pumpAndSettle();

    expect(find.text('Building blocks'), findsOneWidget);
    expect(find.text('Properties'), findsOneWidget);
    // Palette groups.
    // Each appears in the palette heading and again on the node boxes, where
    // the family is written out so colour is never the only signal.
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Processors'), findsWidgets);
    expect(find.text('Destinations'), findsWidgets);
    // The nodes of the seeded flow are on the canvas.
    expect(find.text('Is it SpO2?'), findsOneWidget);
    expect(find.text('Below 92%?'), findsOneWidget);
    // And it reports itself as ready to run.
    expect(find.text('The flow is ready to run.'), findsOneWidget);
  });

  testWidgets('selecting a filter block shows its condition', (tester) async {
    await pumpEai(tester);
    await tester.tap(find.text('Low SpO2 alert'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Below 92%?'));
    await tester.pumpAndSettle();

    expect(find.text('Filter'), findsWidgets);
    expect(find.text('Operator'), findsOneWidget);
    // The configured path is shown in an editable field, not as raw JSON.
    expect(
      find.widgetWithText(TextFormField, 'valueQuantity.value'),
      findsWidgets,
    );
  });

  testWidgets('the test panel traces a message through the flow', (
    tester,
  ) async {
    await pumpEai(tester);
    await tester.tap(find.text('Low SpO2 alert'));
    await tester.pumpAndSettle();

    expect(find.text('Test message'), findsOneWidget);
    expect(
      find.text('Run the flow to see what happens at each step.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    // The default sample is an SpO2 of 88, so the alert must fire and every
    // step must be visible.
    expect(find.text('Trace'), findsOneWidget);
    expect(find.text('Delivered'), findsWidgets);
    expect(find.text('Build alert'), findsWidgets);
  });

  testWidgets('the message log is empty until something runs for real', (
    tester,
  ) async {
    await pumpEai(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Message log'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No messages yet.'), findsOneWidget);
  });

  testWidgets('everything translates', (tester) async {
    await pumpEai(tester);

    await tester.tap(find.text('NL'));
    await tester.pumpAndSettle();
    expect(find.text('Interoperabiliteitsserver'), findsOneWidget);
    expect(find.text('Alarm lage SpO2'), findsOneWidget);

    await tester.tap(find.text('FR'));
    await tester.pumpAndSettle();
    expect(find.text("Serveur d'interopérabilité"), findsOneWidget);
    expect(find.text('Alerte SpO2 basse'), findsOneWidget);
  });
}
