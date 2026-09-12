import 'package:eai_app/src/services/flow_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hospital_core/hospital_core.dart';

IntegrationFlow emptyFlow() => IntegrationFlow(
  id: 'flow-test',
  name: const LocalizedText.same('Test'),
  description: const LocalizedText.same(''),
  isEnabled: true,
  nodes: const <FlowNode>[],
  connections: const <FlowConnection>[],
  updatedAt: DateTime.utc(2026, 9, 12),
);

void main() {
  group('building a flow on the canvas', () {
    test('dropping a block adds it and selects it', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final node = controller.addNode(FlowNodeType.deviceSource, 100, 200);

      expect(controller.flow.nodes, hasLength(1));
      expect(controller.selectedNodeId, node.id);
      expect(node.x, 100);
      expect(node.y, 200);
    });

    test('a new block arrives configured, not empty', () {
      final controller = FlowEditorController(flow: emptyFlow());

      final filter = controller.addNode(FlowNodeType.filter, 0, 0);
      expect(filter.config['path'], isNotEmpty);
      expect(filter.config['operator'], 'equals');

      final mapper = controller.addNode(FlowNodeType.mapper, 0, 0);
      expect(mapper.config['mappings'], isEmpty);
      expect(mapper.config['keepUnmapped'], false);

      final enricher = controller.addNode(FlowNodeType.enricher, 0, 0);
      expect(enricher.config['path'], 'subject.reference');
    });

    test('dragging a block cannot push it off the canvas', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final node = controller.addNode(FlowNodeType.filter, 50, 50);

      controller.moveNode(node.id, -300, -300);
      final moved = controller.flow.nodeById(node.id)!;
      expect(moved.x, 0);
      expect(moved.y, 0);
    });

    test('connecting two blocks draws exactly one wire', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final source = controller.addNode(FlowNodeType.deviceSource, 0, 0);
      final sink = controller.addNode(FlowNodeType.logDestination, 300, 0);

      controller.startConnection(source.id);
      expect(controller.isConnecting, isTrue);
      expect(controller.completeConnection(sink.id), isTrue);

      expect(controller.flow.connections, hasLength(1));
      expect(controller.isConnecting, isFalse);
    });

    test('the same wire cannot be drawn twice', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final source = controller.addNode(FlowNodeType.deviceSource, 0, 0);
      final sink = controller.addNode(FlowNodeType.logDestination, 300, 0);

      controller.startConnection(source.id);
      controller.completeConnection(sink.id);
      controller.startConnection(source.id);

      // A duplicate edge would double every message that crossed it.
      expect(controller.completeConnection(sink.id), isFalse);
      expect(controller.flow.connections, hasLength(1));
    });

    test('a block cannot be wired to itself', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final node = controller.addNode(FlowNodeType.mapper, 0, 0);

      controller.startConnection(node.id);
      expect(controller.completeConnection(node.id), isFalse);
      expect(controller.flow.connections, isEmpty);
    });

    test('nothing can be wired into a source', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final mapper = controller.addNode(FlowNodeType.mapper, 0, 0);
      final source = controller.addNode(FlowNodeType.deviceSource, 300, 0);

      controller.startConnection(mapper.id);
      expect(controller.completeConnection(source.id), isFalse);
      expect(controller.flow.connections, isEmpty);
    });

    test('deleting a block takes its wires with it', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final source = controller.addNode(FlowNodeType.deviceSource, 0, 0);
      final middle = controller.addNode(FlowNodeType.validator, 200, 0);
      final sink = controller.addNode(FlowNodeType.logDestination, 400, 0);

      controller.startConnection(source.id);
      controller.completeConnection(middle.id);
      controller.startConnection(middle.id);
      controller.completeConnection(sink.id);
      expect(controller.flow.connections, hasLength(2));

      controller.deleteNode(middle.id);

      // A dangling edge would silently break the flow.
      expect(controller.flow.nodes, hasLength(2));
      expect(controller.flow.connections, isEmpty);
      // Deleting some other block leaves the selection where it was.
      expect(controller.selectedNodeId, sink.id);

      // Deleting the selected block does clear it.
      controller.deleteNode(sink.id);
      expect(controller.selectedNodeId, isNull);
    });

    test('a router can fan out to several destinations by port', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final source = controller.addNode(FlowNodeType.adtSource, 0, 0);
      final router = controller.addNode(FlowNodeType.router, 200, 0);
      final ehr = controller.addNode(
        FlowNodeType.applicationDestination,
        400,
        0,
      );
      final pharm = controller.addNode(
        FlowNodeType.applicationDestination,
        400,
        200,
      );

      controller.startConnection(source.id);
      controller.completeConnection(router.id);
      controller.startConnection(router.id, port: 'admission');
      controller.completeConnection(ehr.id);
      controller.startConnection(router.id, port: 'discharge');
      controller.completeConnection(pharm.id);

      expect(
        controller.flow.successorsOf(router.id, port: 'admission').single.id,
        ehr.id,
      );
      expect(
        controller.flow.successorsOf(router.id, port: 'discharge').single.id,
        pharm.id,
      );
    });
  });

  group('undo', () {
    test('reverses adding a block', () {
      final controller = FlowEditorController(flow: emptyFlow());
      controller.addNode(FlowNodeType.filter, 0, 0);
      expect(controller.flow.nodes, hasLength(1));

      controller.undo();
      expect(controller.flow.nodes, isEmpty);
    });

    test('a whole drag is one step, not one per pixel', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final node = controller.addNode(FlowNodeType.filter, 0, 0);

      controller.beginDrag();
      for (var i = 1; i <= 40; i++) {
        controller.moveNode(node.id, i.toDouble(), i.toDouble());
      }
      expect(controller.flow.nodeById(node.id)!.x, 40);

      controller.undo();
      expect(controller.flow.nodeById(node.id)!.x, 0);
    });

    test('does nothing when there is nothing to undo', () {
      final controller = FlowEditorController(flow: emptyFlow());
      expect(controller.canUndo, isFalse);
      controller.undo();
      expect(controller.flow.nodes, isEmpty);
    });
  });

  group('unsaved changes', () {
    test('a fresh controller is clean', () {
      final controller = FlowEditorController(flow: emptyFlow());
      expect(controller.isDirty, isFalse);
    });

    test('editing marks it dirty and saving clears it', () {
      final controller = FlowEditorController(flow: emptyFlow());
      controller.addNode(FlowNodeType.filter, 0, 0);
      expect(controller.isDirty, isTrue);

      controller.markSaved(controller.flow);
      expect(controller.isDirty, isFalse);
    });

    test('moving a block counts as a change', () {
      final controller = FlowEditorController(flow: emptyFlow());
      final node = controller.addNode(FlowNodeType.filter, 0, 0);
      controller.markSaved(controller.flow);

      controller.moveNode(node.id, 120, 40);
      expect(controller.isDirty, isTrue);
    });
  });

  group('live validation', () {
    test('an empty canvas reports that it is empty', () {
      final controller = FlowEditorController(flow: emptyFlow());
      expect(controller.issues, hasLength(1));
    });

    test('issues clear as the flow is completed', () {
      final controller = FlowEditorController(flow: emptyFlow());

      final source = controller.addNode(FlowNodeType.deviceSource, 0, 0);
      expect(controller.issues, isNotEmpty);

      final sink = controller.addNode(FlowNodeType.logDestination, 300, 0);
      expect(
        controller.issues,
        isNotEmpty,
        reason: 'the two blocks are not wired together yet',
      );

      controller.startConnection(source.id);
      controller.completeConnection(sink.id);
      expect(controller.issues, isEmpty);
    });

    test('an issue points at the block that caused it', () {
      final controller = FlowEditorController(flow: emptyFlow());
      controller.addNode(FlowNodeType.deviceSource, 0, 0);
      final orphan = controller.addNode(FlowNodeType.logDestination, 300, 0);

      expect(controller.issues.map((i) => i.nodeId), contains(orphan.id));
    });
  });

  group('a flow built on the canvas actually runs', () {
    test('drawn by hand, it filters and delivers correctly', () async {
      final controller = FlowEditorController(flow: emptyFlow());

      // Source → "is it SpO2?" → "below 92?" → log
      final source = controller.addNode(FlowNodeType.deviceSource, 0, 0);
      final isSpo2 = controller.addNode(FlowNodeType.filter, 200, 0);
      final isLow = controller.addNode(FlowNodeType.filter, 400, 0);
      final log = controller.addNode(FlowNodeType.logDestination, 600, 0);

      controller.setNodeConfig(isSpo2.id, <String, dynamic>{
        'path': 'code.coding.0.code',
        'operator': 'equals',
        'value': '2708-6',
      });
      controller.setNodeConfig(isLow.id, <String, dynamic>{
        'path': 'valueQuantity.value',
        'operator': 'lessThan',
        'value': '92',
      });

      controller.startConnection(source.id);
      controller.completeConnection(isSpo2.id);
      controller.startConnection(isSpo2.id);
      controller.completeConnection(isLow.id);
      controller.startConnection(isLow.id);
      controller.completeConnection(log.id);

      expect(controller.issues, isEmpty);

      final engine = FlowEngine(FlowExecutionContext.dryRun());

      Future<MessageStatus> run(double saturation) async {
        final observation = Observation(
          id: 'o',
          patientId: 'pat-001',
          type: VitalSignType.oxygenSaturation,
          value: saturation,
          effectiveDateTime: DateTime.utc(2026, 9, 12),
        );
        final result = await engine.run(
          controller.flow,
          IntegrationMessage(
            id: 'm',
            messageType: 'Observation',
            sourceApp: 'DEV3',
            payload: observation.toFhir(),
            status: MessageStatus.received,
            receivedAt: DateTime.utc(2026, 9, 12),
          ),
        );
        return result.status;
      }

      expect(await run(88), MessageStatus.delivered);
      expect(await run(97), MessageStatus.filtered);
    });
  });
}
