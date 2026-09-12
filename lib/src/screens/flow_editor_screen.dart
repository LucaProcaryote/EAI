import 'package:flutter/material.dart';
import 'package:hospital_core/hospital_core.dart';
import 'package:provider/provider.dart';

import '../services/flow_editor_controller.dart';
import '../widgets/flow_canvas.dart';
import '../widgets/flow_test_panel.dart';
import '../widgets/node_palette.dart';
import '../widgets/node_properties.dart';

/// The visual integration editor: palette, canvas, properties, test panel.
class FlowEditorScreen extends StatefulWidget {
  const FlowEditorScreen({super.key, required this.flow});

  final IntegrationFlow flow;

  @override
  State<FlowEditorScreen> createState() => _FlowEditorScreenState();
}

class _FlowEditorScreenState extends State<FlowEditorScreen> {
  late final FlowEditorController _controller = FlowEditorController(
    flow: widget.flow,
  );

  bool _showTestPanel = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repository = context.read<HospitalRepository>();
    final l10n = HospitalLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final saved = await repository.saveFlow(_controller.flow);
    _controller.markSaved(saved);
    messenger.showSnackBar(SnackBar(content: Text(l10n.eaiFlowSaved)));
  }

  Future<bool> _confirmDiscard() async {
    if (!_controller.isDirty) return true;
    final l10n = HospitalLocalizations.of(context);

    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.labelUnsavedChanges),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.labelDiscardChanges),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = HospitalLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;

    return ChangeNotifierProvider<FlowEditorController>.value(
      value: _controller,
      child: Consumer<FlowEditorController>(
        builder: (context, controller, _) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            if (await _confirmDiscard() && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(controller.flow.name.forLanguage(language)),
              actions: <Widget>[
                if (controller.isDirty)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.sm),
                    child: Center(
                      child: StatusChip(
                        label: l10n.labelUnsavedChanges,
                        color: HospitalTheme.warningOf(context),
                        dense: true,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo),
                  onPressed: controller.canUndo ? controller.undo : null,
                ),
                IconButton(
                  tooltip: l10n.eaiTestFlow,
                  icon: Icon(
                    _showTestPanel ? Icons.science : Icons.science_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _showTestPanel = !_showTestPanel),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save, size: 18),
                    label: Text(l10n.eaiSaveFlow),
                  ),
                ),
              ],
            ),
            body: Column(
              children: <Widget>[
                if (controller.isConnecting)
                  Material(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.md,
                        vertical: Gap.sm,
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.linear_scale, size: 16),
                          Gap.w8,
                          Expanded(child: Text(l10n.eaiConnectHint)),
                          TextButton(
                            onPressed: controller.cancelConnection,
                            child: Text(l10n.actionCancel),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Expanded(
                  child: Row(
                    children: <Widget>[
                      SizedBox(width: 220, child: NodePalette()),
                      VerticalDivider(width: 1),
                      Expanded(child: FlowCanvas()),
                      VerticalDivider(width: 1),
                      SizedBox(width: 320, child: NodeProperties()),
                    ],
                  ),
                ),
                if (_showTestPanel) ...<Widget>[
                  const Divider(height: 1),
                  const SizedBox(height: 280, child: FlowTestPanel()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
