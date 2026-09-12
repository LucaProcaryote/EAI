import 'package:flutter/foundation.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:uuid/uuid.dart';

/// Runs the integration engine on top of the repository and the FHIR server.
///
/// The engine itself ([FlowEngine]) is pure and lives in `hospital_core`; this
/// class supplies the side effects - looking a patient up, writing to FHIR,
/// delivering to an application - and keeps the message log.
class EngineService extends ChangeNotifier {
  EngineService({required this.repository, required this.fhir, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final HospitalRepository repository;
  final FhirClient fhir;
  final Uuid _uuid;

  bool? _fhirReachable;

  /// Null until the first check has finished.
  bool? get fhirReachable => _fhirReachable;

  Future<void> checkFhirServer() async {
    _fhirReachable = await fhir.isReachable();
    notifyListeners();
  }

  /// The side effects a flow is allowed to perform.
  ///
  /// [dryRun] keeps everything in memory so the editor's Test button can show
  /// exactly what a flow would do without doing it.
  FlowExecutionContext context({bool dryRun = false}) {
    if (dryRun) {
      return FlowExecutionContext(
        lookupPatient: repository.resolvePatient,
        writeToFhirStore: (resource) async =>
            '${resource['resourceType']}/${resource['id'] ?? 'preview'} (not written)',
        deliverToApplication: (_, __) async {},
        postToUrl: (_, __) async {},
      );
    }
    return FlowExecutionContext(
      lookupPatient: repository.resolvePatient,
      writeToFhirStore: (resource) async {
        final stored = await fhir.update(resource);
        return '${stored['resourceType']}/${stored['id']}';
      },
      deliverToApplication: (app, payload) async {
        // Applications share the database in this teaching hospital, so
        // "delivering" means writing through the repository the receiving
        // application reads. A production engine would call each system's own
        // API; the flow does not need to know the difference.
        await _deliver(app, payload);
      },
      postToUrl: (url, payload) async {
        throw UnsupportedError(
          'Outbound HTTP is disabled in the classroom build ($url)',
        );
      },
    );
  }

  Future<void> _deliver(String app, Map<String, dynamic> payload) async {
    final resourceType = payload['resourceType']?.toString();
    if (resourceType == 'Observation') {
      await repository.addObservation(Observation.fromFhir(payload));
    }
    // Other resource types are accepted and logged; wiring each one into its
    // receiving application is one of the lab exercises.
  }

  /// Puts [message] through [flow] and records the result.
  Future<IntegrationMessage> run(
    IntegrationFlow flow,
    IntegrationMessage message, {
    bool dryRun = false,
  }) async {
    final engine = FlowEngine(context(dryRun: dryRun));
    final result = await engine.run(flow, message);

    if (!dryRun) {
      await repository.saveMessage(result);
      await repository.saveFlow(
        flow.copyWith(
          messagesProcessed: flow.messagesProcessed + 1,
          messagesFailed:
              flow.messagesFailed +
              (result.status == MessageStatus.failed ? 1 : 0),
        ),
      );
    }
    notifyListeners();
    return result;
  }

  /// Builds a message from a raw payload, for the test panel and for anything
  /// posted at the engine's inbox.
  IntegrationMessage messageFrom(
    Map<String, dynamic> payload, {
    String sourceApp = 'TEST',
    String? messageType,
  }) => IntegrationMessage(
    id: 'msg-${_uuid.v4()}',
    messageType:
        messageType ??
        payload['resourceType']?.toString() ??
        payload['type']?.toString() ??
        'unknown',
    sourceApp: sourceApp,
    payload: payload,
    status: MessageStatus.received,
    receivedAt: DateTime.now(),
    patientId: _patientIdIn(payload),
  );

  String? _patientIdIn(Map<String, dynamic> payload) {
    final reference = readPath(payload, 'subject.reference')?.toString();
    if (reference != null && reference.startsWith('Patient/')) {
      return reference.substring(8);
    }
    return (payload['patient_id'] ?? payload['patientId'])?.toString();
  }

  /// Writes the whole fictive hospital to the FHIR server as one transaction
  /// bundle, so the students have real resources to search against.
  Future<int> seedFhirServer() async {
    final resources = <Map<String, dynamic>>[];

    for (final patient in await repository.listPatients()) {
      resources.add(patient.toFhir());
      for (final allergy in patient.allergies) {
        resources.add(allergy.toFhir());
      }
    }
    for (final encounter in await repository.listEncounters()) {
      resources.add(encounter.toFhir());
    }
    for (final device in await repository.listDevices()) {
      resources.add(device.toFhir());
    }
    // Observations are by far the most numerous; a slice is enough to search.
    final observations = await repository.listObservations(limit: 400);
    for (final observation in observations) {
      resources.add(observation.toFhir());
    }
    for (final prescription in await repository.listPrescriptions()) {
      resources.add(prescription.toFhir());
    }

    final bundle = <String, dynamic>{
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': <dynamic>[
        for (final resource in resources)
          <String, dynamic>{
            'resource': resource,
            'request': <String, dynamic>{
              // Update-as-create: the mini-hospital already owns stable ids,
              // and this keeps the FHIR server's ids aligned with the
              // application databases so cross-references resolve.
              'method': 'PUT',
              'url': '${resource['resourceType']}/${resource['id']}',
            },
          },
      ],
    };

    await fhir.transaction(bundle);
    await checkFhirServer();
    return resources.length;
  }

  @override
  void dispose() {
    fhir.close();
    super.dispose();
  }
}
