import 'package:flutter/foundation.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:uuid/uuid.dart';

/// The working copy of a flow while it is being edited.
///
/// Editing happens against this rather than against the stored flow, so the
/// canvas stays responsive, undo is possible, and nothing reaches the database
/// until the user saves.
class FlowEditorController extends ChangeNotifier {
  FlowEditorController({required IntegrationFlow flow, Uuid? uuid})
    : _flow = flow,
      _saved = flow,
      _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  IntegrationFlow _flow;
  IntegrationFlow get flow => _flow;

  /// The last state that was written to the repository, for change detection.
  IntegrationFlow _saved;

  final List<IntegrationFlow> _undoStack = <IntegrationFlow>[];
  static const int _undoLimit = 50;

  String? _selectedNodeId;
  String? get selectedNodeId => _selectedNodeId;

  FlowNode? get selectedNode =>
      _selectedNodeId == null ? null : _flow.nodeById(_selectedNodeId!);

  /// The node whose output port was clicked, while a connection is being drawn.
  String? _connectingFromNodeId;
  String? get connectingFromNodeId => _connectingFromNodeId;

  String _connectingFromPort = 'out';
  String get connectingFromPort => _connectingFromPort;

  bool get isConnecting => _connectingFromNodeId != null;
  bool get canUndo => _undoStack.isNotEmpty;

  /// True when there is something worth saving.
  bool get isDirty =>
      _flow.updatedAt != _saved.updatedAt ||
      _flow.nodes.length != _saved.nodes.length ||
      _flow.connections.length != _saved.connections.length ||
      !_sameNodes(_flow.nodes, _saved.nodes);

  List<FlowValidationIssue> get issues => _flow.validate();

  void _mutate(IntegrationFlow next, {bool recordUndo = true}) {
    if (recordUndo) {
      _undoStack.add(_flow);
      if (_undoStack.length > _undoLimit) _undoStack.removeAt(0);
    }
    _flow = next;
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _flow = _undoStack.removeLast();
    _selectedNodeId = null;
    _connectingFromNodeId = null;
    notifyListeners();
  }

  void markSaved(IntegrationFlow saved) {
    _saved = saved;
    _flow = saved;
    notifyListeners();
  }

  // ---- Selection -----------------------------------------------------------

  void select(String? nodeId) {
    _selectedNodeId = nodeId;
    notifyListeners();
  }

  // ---- Nodes ---------------------------------------------------------------

  FlowNode addNode(FlowNodeType type, double x, double y) {
    final node = FlowNode(
      id: 'n-${_uuid.v4().substring(0, 8)}',
      type: type,
      label: '',
      x: x,
      y: y,
      config: _defaultConfig(type),
    );
    _mutate(_flow.copyWith(nodes: <FlowNode>[..._flow.nodes, node]));
    _selectedNodeId = node.id;
    return node;
  }

  /// Sensible starting settings, so a freshly dropped node does something
  /// rather than failing with an empty path.
  static Map<String, dynamic> _defaultConfig(FlowNodeType type) =>
      switch (type) {
        FlowNodeType.filter => <String, dynamic>{
          'path': 'resourceType',
          'operator': 'equals',
          'value': 'Observation',
        },
        FlowNodeType.mapper => <String, dynamic>{
          'mappings': <dynamic>[],
          'keepUnmapped': false,
        },
        FlowNodeType.enricher => <String, dynamic>{
          'path': 'subject.reference',
          'target': 'patient',
        },
        FlowNodeType.router => <String, dynamic>{
          'path': 'type',
          'routes': <dynamic>[],
          'defaultPort': '',
        },
        FlowNodeType.codeTranslator => <String, dynamic>{
          'path': '',
          'table': <String, dynamic>{},
          'onMissing': 'pass',
        },
        FlowNodeType.applicationDestination => <String, dynamic>{'app': 'EHR'},
        FlowNodeType.httpDestination => <String, dynamic>{
          'url': '',
          'method': 'POST',
        },
        _ => const <String, dynamic>{},
      };

  void moveNode(String nodeId, double x, double y) {
    // Dragging produces a stream of updates; recording each one would fill the
    // undo stack with a hundred entries for a single gesture.
    final nodes = <FlowNode>[
      for (final node in _flow.nodes)
        if (node.id == nodeId)
          node.copyWith(x: x < 0 ? 0 : x, y: y < 0 ? 0 : y)
        else
          node,
    ];
    _mutate(_flow.copyWith(nodes: nodes), recordUndo: false);
  }

  /// Call once at the start of a drag so the whole gesture is one undo step.
  void beginDrag() {
    _undoStack.add(_flow);
    if (_undoStack.length > _undoLimit) _undoStack.removeAt(0);
  }

  void updateNode(String nodeId, FlowNode Function(FlowNode) change) {
    final nodes = <FlowNode>[
      for (final node in _flow.nodes)
        if (node.id == nodeId) change(node) else node,
    ];
    _mutate(_flow.copyWith(nodes: nodes));
  }

  void setNodeLabel(String nodeId, String label) =>
      updateNode(nodeId, (node) => node.copyWith(label: label));

  void setNodeConfig(String nodeId, Map<String, dynamic> config) =>
      updateNode(nodeId, (node) => node.copyWith(config: config));

  void deleteNode(String nodeId) {
    _mutate(
      _flow.copyWith(
        nodes: _flow.nodes.where((n) => n.id != nodeId).toList(),
        // A dangling connection would silently break the flow, so remove any
        // edge that touched the deleted node.
        connections: _flow.connections
            .where((c) => c.fromNodeId != nodeId && c.toNodeId != nodeId)
            .toList(),
      ),
    );
    if (_selectedNodeId == nodeId) _selectedNodeId = null;
    if (_connectingFromNodeId == nodeId) _connectingFromNodeId = null;
  }

  // ---- Connections ---------------------------------------------------------

  void startConnection(String nodeId, {String port = 'out'}) {
    _connectingFromNodeId = nodeId;
    _connectingFromPort = port;
    notifyListeners();
  }

  void cancelConnection() {
    _connectingFromNodeId = null;
    notifyListeners();
  }

  /// Completes a connection into [toNodeId]. Returns false and explains
  /// nothing if the link would be invalid - the caller shows the message.
  bool completeConnection(String toNodeId) {
    final from = _connectingFromNodeId;
    _connectingFromNodeId = null;
    if (from == null || from == toNodeId) {
      notifyListeners();
      return false;
    }

    final target = _flow.nodeById(toNodeId);
    if (target == null || !target.type.hasInput) {
      notifyListeners();
      return false;
    }

    // Adding the same edge twice would double every message that crosses it.
    final exists = _flow.connections.any(
      (c) =>
          c.fromNodeId == from &&
          c.toNodeId == toNodeId &&
          c.fromPort == _connectingFromPort,
    );
    if (exists) {
      notifyListeners();
      return false;
    }

    _mutate(
      _flow.copyWith(
        connections: <FlowConnection>[
          ..._flow.connections,
          FlowConnection(
            id: 'c-${_uuid.v4().substring(0, 8)}',
            fromNodeId: from,
            toNodeId: toNodeId,
            fromPort: _connectingFromPort,
          ),
        ],
      ),
    );
    return true;
  }

  void deleteConnection(String connectionId) {
    _mutate(
      _flow.copyWith(
        connections: _flow.connections
            .where((c) => c.id != connectionId)
            .toList(),
      ),
    );
  }

  // ---- Flow-level ----------------------------------------------------------

  void setName(LocalizedText name) => _mutate(_flow.copyWith(name: name));

  void setDescription(LocalizedText description) =>
      _mutate(_flow.copyWith(description: description));

  void setEnabled(bool enabled) => _mutate(_flow.copyWith(isEnabled: enabled));

  static bool _sameNodes(List<FlowNode> a, List<FlowNode> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].label != b[i].label ||
          a[i].x != b[i].x ||
          a[i].y != b[i].y ||
          a[i].config.toString() != b[i].config.toString()) {
        return false;
      }
    }
    return true;
  }
}
