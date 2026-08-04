import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'diagram.dart';
import 'models.dart';

/// What an edit sheet hands back once the user saves.
class GearDraft {
  const GearDraft({
    required this.name,
    required this.width,
    required this.height,
    this.depth,
    this.rotatable = true,
  });

  final String name;
  final double width;
  final double height;
  final double? depth;
  final bool rotatable;
}

/// Shared editor for containers and goods — both are a name, two required
/// dimensions and an optional depth.
class GearEditSheet extends StatefulWidget {
  const GearEditSheet({
    super.key,
    required this.title,
    required this.nameLabel,
    this.initial,
    this.showRotatable = false,
  });

  final String title;
  final String nameLabel;

  /// Null when creating something new.
  final GearDraft? initial;

  /// Goods can be locked to one orientation; containers cannot be turned.
  final bool showRotatable;

  @override
  State<GearEditSheet> createState() => _GearEditSheetState();
}

class _GearEditSheetState extends State<GearEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _depth;
  late bool _rotatable;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _width = TextEditingController(
      text: initial == null ? '' : formatLength(initial.width),
    );
    _height = TextEditingController(
      text: initial == null ? '' : formatLength(initial.height),
    );
    _depth = TextEditingController(
      text: initial?.depth == null ? '' : formatLength(initial!.depth!),
    );
    _rotatable = initial?.rotatable ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _depth.dispose();
    super.dispose();
  }

  String? _validateRequiredNumber(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) return 'Required';
    if (parsed <= 0) return 'Must be above 0';
    return null;
  }

  String? _validateOptionalNumber(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Not a number';
    if (parsed <= 0) return 'Must be above 0';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final depthText = _depth.text.trim();
    Navigator.of(context).pop(
      GearDraft(
        name: _name.text.trim(),
        width: double.parse(_width.text.trim()),
        height: double.parse(_height.text.trim()),
        depth: depthText.isEmpty ? null : double.parse(depthText),
        rotatable: _rotatable,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: widget.nameLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Required' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DimensionField(
                    controller: _width,
                    label: 'Width',
                    validator: _validateRequiredNumber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DimensionField(
                    controller: _height,
                    label: 'Height',
                    validator: _validateRequiredNumber,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DimensionField(
                    controller: _depth,
                    label: 'Depth',
                    hint: 'optional',
                    validator: _validateOptionalNumber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Measurements in centimetres. Add a depth to get a side view '
              'and a volume check.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (widget.showRotatable) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _rotatable,
                onChanged: (value) => setState(() => _rotatable = value),
                title: const Text('Can be turned'),
                subtitle: const Text(
                  'Let the packer rotate this to make it fit',
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _submit, child: const Text('Save')),
          ],
        ),
      ),
    );
  }
}

class _DimensionField extends StatelessWidget {
  const _DimensionField({
    required this.controller,
    required this.label,
    required this.validator,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: 'cm',
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}

/// Opens [GearEditSheet] as a modal and returns the draft, or null if
/// cancelled.
Future<GearDraft?> showGearEditSheet(
  BuildContext context, {
  required String title,
  required String nameLabel,
  GearDraft? initial,
  bool showRotatable = false,
}) {
  return showModalBottomSheet<GearDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => GearEditSheet(
      title: title,
      nameLabel: nameLabel,
      initial: initial,
      showRotatable: showRotatable,
    ),
  );
}

/// Convenience for turning an existing good into a draft for editing.
GearDraft draftFromGood(Good good) => GearDraft(
  name: good.name,
  width: good.width,
  height: good.height,
  depth: good.depth,
  rotatable: good.rotatable,
);

/// Convenience for turning an existing container into a draft for editing.
GearDraft draftFromContainer(GearContainer container) => GearDraft(
  name: container.name,
  width: container.width,
  height: container.height,
  depth: container.depth,
);
