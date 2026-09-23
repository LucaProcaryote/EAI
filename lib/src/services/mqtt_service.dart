import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hospital_core/hospital_core.dart';

import 'engine_service.dart';

/// Holds the engine's connection to the MQTT broker and feeds what arrives
/// into the flows that asked for it.
///
/// The connection lives in the browser, with this page. That is a real
/// limitation and worth saying plainly to the students: readings published
/// while nobody has the integration engine open are not queued anywhere, they
/// are simply missed. A production engine is a server that never closes its
/// tab. Making the limitation visible is better than hiding it behind
/// something that looks like durability and is not.
class MqttService extends ChangeNotifier {
  MqttService({
    required this.engine,
    required this.repository,
    required this.settings,
    MqttTransport? transport,
  }) : _transport = transport;

  final EngineService engine;
  final HospitalRepository repository;
  final MqttSettings settings;

  MqttTransport? _transport;
  DeviceFeed? _feed;
  StreamSubscription<FeedEvent>? _events;
  StreamSubscription<MqttLinkState>? _states;

  MqttLinkState _state = MqttLinkState.disconnected;
  String? _error;
  int _received = 0;
  int _processed = 0;
  final Map<String, PresenceMessage> _presence = <String, PresenceMessage>{};

  MqttLinkState get state => _state;

  /// Why the last attempt failed, or null. Shown rather than logged: a broker
  /// that refuses the credentials is the most likely misconfiguration, and it
  /// is invisible otherwise.
  String? get error => _error;

  /// Readings that arrived, and readings a flow actually handled. They differ
  /// whenever a message matched no enabled flow, which is a common and
  /// perfectly quiet way for a lab exercise to appear broken.
  int get received => _received;
  int get processed => _processed;

  Map<String, PresenceMessage> get presence => Map.unmodifiable(_presence);

  bool get isConfigured => settings.isConfigured;

  /// Opens the connection and subscribes to what the enabled flows ask for.
  Future<void> connect() async {
    if (!isConfigured) {
      _error = 'No broker is configured for this build.';
      notifyListeners();
      return;
    }
    await disconnect();

    final transport = _transport ??= MqttClientTransport(settings);
    final feed = _feed = DeviceFeed(transport);
    _states = transport.states.listen((next) {
      _state = next;
      notifyListeners();
    });
    _events = feed.events.listen(_onEvent);

    try {
      _error = null;
      _state = MqttLinkState.connecting;
      notifyListeners();
      await feed.connectAsObserver(readings: await _subscriptionFilter());
      _state = MqttLinkState.connected;
    } catch (error) {
      _state = MqttLinkState.failed;
      _error = '$error';
    }
    notifyListeners();
  }

  /// The filter to subscribe to: the broadest one any enabled flow asks for.
  ///
  /// Subscribing once to the union rather than once per flow keeps a single
  /// stream of messages, which is also how the trace stays readable - one
  /// arrival, then whichever flows match it.
  Future<String> _subscriptionFilter() async {
    final filters = <String>{};
    for (final flow in await repository.listFlows()) {
      if (!flow.isEnabled) continue;
      for (final node in flow.nodes) {
        if (node.type != FlowNodeType.mqttSource) continue;
        final filter = (node.config['filter'] ?? '').toString();
        if (filter.isNotEmpty) filters.add(filter);
      }
    }
    if (filters.isEmpty) return MqttTopics.allReadings;
    if (filters.length == 1) return filters.first;
    // More than one flow, each with its own filter: subscribing to the root
    // and letting the per-flow filters decide is simpler than reconciling
    // overlapping wildcards, and the broker does the work either way.
    return MqttTopics.allReadings;
  }

  Future<void> _onEvent(FeedEvent event) async {
    switch (event) {
      case PresenceEvent(:final status):
        _presence[status.deviceId] = status;
        notifyListeners();
      case MalformedEvent(:final topic, :final reason):
        _error = 'Unreadable message on $topic: $reason';
        notifyListeners();
      case ReadingEvent(:final reading, :final topic):
        _received++;
        notifyListeners();
        await _runFlowsFor(reading, topic);
    }
  }

  Future<void> _runFlowsFor(DeviceReading reading, String topic) async {
    final message = engine.messageFrom(
      <String, dynamic>{...reading.toJson(), 'topic': topic},
      sourceApp: reading.deviceId,
      messageType: 'Reading',
    );

    for (final flow in await repository.listFlows()) {
      if (!flow.isEnabled) continue;
      final source = flow.nodes
          .where((n) => n.type == FlowNodeType.mqttSource)
          .where(
            (n) => MqttTopics.matches(
              (n.config['filter'] ?? MqttTopics.allReadings).toString(),
              topic,
            ),
          )
          .firstOrNull;
      if (source == null) continue;
      await engine.run(flow, message);
      _processed++;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _events?.cancel();
    await _states?.cancel();
    _events = null;
    _states = null;
    await _feed?.close();
    _feed = null;
    if (_transport case final MqttClientTransport transport) {
      await transport.disconnect();
    }
    _state = MqttLinkState.disconnected;
  }

  @override
  void dispose() {
    unawaited(disconnect());
    super.dispose();
  }
}
