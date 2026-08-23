import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'diagram.dart';
import 'models.dart';
import 'preview_3d.dart' show Vec3, rotate3;
import 'units.dart';

/// A dimension field that reads and writes the user's chosen unit while the
/// value it yields is always centimetres.
class DimensionField extends StatelessWidget {
  const DimensionField({
    super.key,
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
        suffixText: UnitScope.of(context).symbol,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}

String? _requiredNumber(String? value) {
  final parsed = double.tryParse((value ?? '').trim());
  if (parsed == null) return 'Required';
  if (parsed <= 0) return 'Must be above 0';
  return null;
}

String? _optionalNumber(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  if (parsed == null) return 'Not a number';
  if (parsed <= 0) return 'Must be above 0';
  return null;
}

String? _optionalNonNegativeNumber(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final parsed = double.tryParse(text);
  if (parsed == null) return 'Not a number';
  if (parsed < 0) return 'Cannot be negative';
  return null;
}

/// What the gear sheet hands back. All lengths in centimetres.
class GearItemDraft {
  const GearItemDraft({
    required this.name,
    required this.width,
    required this.height,
    this.depth,
    this.rotatable = true,
    this.tags = const [],
    this.isContainer = false,
  });

  final String name;
  final double width;
  final double height;
  final double? depth;
  final bool rotatable;
  final List<String> tags;
  final bool isContainer;
}

/// What the plan sheet hands back. [tolerance] and [heightOverflow] are in
/// centimetres.
class PlanDraft {
  const PlanDraft({
    required this.name,
    required this.containerItemId,
    this.tolerance = 0,
    this.heightOverflow = 0,
  });

  final String name;
  final String containerItemId;
  final double tolerance;
  final double heightOverflow;
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- gear

class GearItemSheet extends StatefulWidget {
  const GearItemSheet({super.key, this.initial, this.knownTags = const []});

  /// Null when creating something new.
  final GearItem? initial;

  /// Tags already used elsewhere, offered as one-tap suggestions.
  final List<String> knownTags;

  @override
  State<GearItemSheet> createState() => _GearItemSheetState();
}

class _GearItemSheetState extends State<GearItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _depth;
  late final TextEditingController _tag;
  late bool _rotatable;
  late List<String> _tags;
  late bool _isContainer;

  MeasurementUnit get _unit => UnitScope.of(context);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _width = TextEditingController();
    _height = TextEditingController();
    _depth = TextEditingController();
    _tag = TextEditingController();
    _rotatable = widget.initial?.rotatable ?? true;
    _tags = [...?widget.initial?.tags];
    _isContainer = widget.initial?.isContainer ?? false;
  }

  var _didFillDimensions = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The unit is only reachable from context, so the stored centimetre values
    // are converted for display here rather than in initState.
    if (_didFillDimensions) return;
    _didFillDimensions = true;

    final initial = widget.initial;
    if (initial == null) return;
    _width.text = _unit.format(initial.width);
    _height.text = _unit.format(initial.height);
    _depth.text = initial.depth == null ? '' : _unit.format(initial.depth!);
  }

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    _depth.dispose();
    _tag.dispose();
    super.dispose();
  }

  /// The number in [controller] for the axis diagram's proportions, or
  /// [fallback] while the field is empty or not a valid positive number - the
  /// diagram is a shape reference, not a live measurement, so it should never
  /// collapse to nothing just because a field hasn't been typed into yet.
  double _previewValue(TextEditingController controller, double fallback) {
    final value = double.tryParse(controller.text.trim());
    return (value == null || value <= 0) ? fallback : value;
  }

  void _addTag(String raw) {
    final cleaned = normaliseTags([..._tags, raw]);
    setState(() => _tags = cleaned);
    _tag.clear();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final depthText = _depth.text.trim();
    Navigator.of(context).pop(
      GearItemDraft(
        name: _name.text.trim(),
        width: _unit.toCentimetres(double.parse(_width.text.trim())),
        height: _unit.toCentimetres(double.parse(_height.text.trim())),
        depth: depthText.isEmpty
            ? null
            : _unit.toCentimetres(double.parse(depthText)),
        rotatable: _rotatable,
        tags: _tags,
        isContainer: _isContainer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = widget.knownTags
        .where((tag) => !_tags.contains(tag))
        .toList();

    return Form(
      key: _formKey,
      child: _SheetShell(
        title: widget.initial == null ? 'New gear' : 'Edit gear',
        children: [
          TextFormField(
            controller: _name,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          // X/Y/Z reading order left to right, matching the diagram below -
          // width then depth then height, not the width/height/depth order
          // those words would suggest.
          Row(
            children: [
              Expanded(
                child: DimensionField(
                  controller: _width,
                  label: PlanAxis.width.axisLetter,
                  validator: _requiredNumber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DimensionField(
                  controller: _depth,
                  label: PlanAxis.depth.axisLetter,
                  hint: 'optional',
                  validator: _optionalNumber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DimensionField(
                  controller: _height,
                  label: PlanAxis.height.axisLetter,
                  validator: _requiredNumber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: Listenable.merge([_width, _depth, _height]),
            builder: (context, _) => _AxisPreview(
              width: _previewValue(_width, 40),
              depth: _previewValue(_depth, 25),
              height: _previewValue(_height, 30),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'X is width, Y is depth (front-to-back), Z is height. Depth is '
            'optional; without it this is flat gear.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tag,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'camp, cook, edc',
              border: OutlineInputBorder(),
              helperText: 'Comma or enter to add',
            ),
            onSubmitted: _addTag,
            onChanged: (value) {
              if (value.endsWith(',')) _addTag(value);
            },
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () =>
                        setState(() => _tags = [..._tags]..remove(tag)),
                  ),
              ],
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in suggestions.take(12))
                  ActionChip(label: Text(tag), onPressed: () => _addTag(tag)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _rotatable,
            onChanged: (value) => setState(() => _rotatable = value),
            title: const Text('Can be turned'),
            subtitle: const Text('Let the packer rotate this to make it fit'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isContainer,
            onChanged: (value) => setState(() => _isContainer = value),
            title: const Text('Holds other gear'),
            subtitle: const Text(
              'Lets you build a plan around it. It can still be packed inside '
              'something bigger.',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}

Future<GearItemDraft?> showGearItemSheet(
  BuildContext context, {
  GearItem? initial,
  List<String> knownTags = const [],
}) {
  final unit = UnitScope.of(context);
  return showModalBottomSheet<GearItemDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => UnitScope(
      unit: unit,
      child: GearItemSheet(initial: initial, knownTags: knownTags),
    ),
  );
}

/// A small fixed-angle reference box showing which typed number becomes
/// which axis - width/depth/height alone reads as three interchangeable
/// numbers, but seeing them as an actual box's X/Y/Z make it obvious depth
/// runs along the ground rather than being how deep a basin is.
///
/// Not to scale in any absolute sense, and never interactive - it exists to
/// teach the mapping, not to preview the real item, so a shape reference
/// with sane fallbacks for empty fields does the job.
class _AxisPreview extends StatelessWidget {
  const _AxisPreview({
    required this.width,
    required this.depth,
    required this.height,
  });

  final double width;
  final double depth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _AxisPreviewPainter(
          width: width,
          depth: depth,
          height: height,
          wireColor: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AxisPreviewPainter extends CustomPainter {
  _AxisPreviewPainter({
    required this.width,
    required this.depth,
    required this.height,
    required this.wireColor,
  });

  final double width;
  final double depth;
  final double height;
  final Color wireColor;

  // The same 3/4 angle Preview3D starts at, for a consistent visual
  // language between the two.
  static const _azimuth = -math.pi / 4;
  static const _elevation = math.pi / 6;

  static const _axisColors = {
    'X': Color(0xFFEF5350),
    'Y': Color(0xFF66BB6A),
    'Z': Color(0xFF42A5F5),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final center = (width / 2, height / 2, depth / 2);
    final diagonal = math.sqrt(width * width + height * height + depth * depth);
    final scale = diagonal <= 0
        ? 1.0
        : (math.min(size.width, size.height) * 0.6) / diagonal;
    final origin = Offset(size.width / 2, size.height / 2 + 6);

    Offset project(Vec3 point) {
      final relative = (
        point.$1 - center.$1,
        point.$2 - center.$2,
        point.$3 - center.$3,
      );
      final rotated = rotate3(relative, _azimuth, _elevation);
      return origin + Offset(rotated.$1, -rotated.$2) * scale;
    }

    final corners = [
      for (final x in [0.0, width])
        for (final y in [0.0, height])
          for (final z in [0.0, depth]) (x, y, z),
    ];
    const edges = [
      [0, 1],
      [0, 2],
      [0, 4],
      [3, 1],
      [3, 2],
      [3, 7],
      [5, 1],
      [5, 4],
      [5, 7],
      [6, 2],
      [6, 4],
      [6, 7],
    ];
    final wirePaint = Paint()
      ..color = wireColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final edge in edges) {
      canvas.drawLine(
        project(corners[edge[0]]),
        project(corners[edge[1]]),
        wirePaint,
      );
    }

    _axis(canvas, project, (width * 1.3, 0, 0), 'X');
    _axis(canvas, project, (0, 0, depth * 1.3), 'Y');
    _axis(canvas, project, (0, height * 1.3, 0), 'Z');
  }

  /// One labelled arrow from the box's own origin corner out to [tip] -
  /// longer than the box itself so it reads as a pointer, not another edge.
  void _axis(
    Canvas canvas,
    Offset Function(Vec3) project,
    Vec3 tip,
    String label,
  ) {
    final color = _axisColors[label]!;
    final start = project((0, 0, 0));
    final end = project(tip);

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, end + const Offset(3, -15));
  }

  @override
  bool shouldRepaint(covariant _AxisPreviewPainter oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.depth != depth ||
      oldDelegate.height != height;
}

// ------------------------------------------------------------- custom units

/// What the custom-unit sheet hands back. [centimetres] is null for a unit
/// derived from gear, whose length comes from that gear instead.
class CustomUnitDraft {
  const CustomUnitDraft({required this.name, this.centimetres, this.axis});

  final String name;
  final double? centimetres;
  final GearAxis? axis;
}

class CustomUnitSheet extends StatefulWidget {
  const CustomUnitSheet({
    super.key,
    required this.definitionUnit,
    this.initial,
    this.sourceItem,
  });

  /// Lengths are typed in this unit — never in the unit being defined, which
  /// would be circular.
  final MeasurementUnit definitionUnit;

  final CustomUnit? initial;

  /// Set when the unit is derived from a piece of gear.
  final GearItem? sourceItem;

  @override
  State<CustomUnitSheet> createState() => _CustomUnitSheetState();
}

class _CustomUnitSheetState extends State<CustomUnitSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _length;
  late GearAxis _axis;

  bool get _isDerived => widget.initial?.isDerived ?? false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _length = TextEditingController(
      text: widget.initial == null
          ? ''
          : widget.definitionUnit.format(widget.initial!.centimetres),
    );
    _axis =
        widget.initial?.sourceAxis ??
        widget.sourceItem?.longestAxis ??
        GearAxis.height;
  }

  @override
  void dispose() {
    _name.dispose();
    _length.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      CustomUnitDraft(
        name: _name.text.trim(),
        centimetres: _isDerived
            ? null
            : widget.definitionUnit.toCentimetres(
                double.parse(_length.text.trim()),
              ),
        axis: _isDerived ? _axis : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.sourceItem;

    return Form(
      key: _formKey,
      child: _SheetShell(
        title: widget.initial == null ? 'New unit' : 'Edit unit',
        children: [
          TextFormField(
            controller: _name,
            autofocus: widget.initial == null,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'hand, notebook, boot',
              border: OutlineInputBorder(),
              helperText: 'Shown after every measurement, so keep it short',
            ),
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          if (_isDerived && item != null) ...[
            Text(
              'Measured by the ${item.name}. Pick which side to measure with — '
              'the length follows the gear, so re-measuring it recalibrates '
              'this unit.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<GearAxis>(
              segments: [
                for (final axis in GearAxis.values)
                  if (item.dimension(axis) != null)
                    ButtonSegment(value: axis, label: Text(axis.label)),
              ],
              selected: {_axis},
              onSelectionChanged: (selection) =>
                  setState(() => _axis = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              '1 ${_name.text.trim().isEmpty ? 'unit' : _name.text.trim()} = '
              '${widget.definitionUnit.formatWithSymbol(item.dimension(_axis) ?? 0)}',
              style: theme.textTheme.bodyMedium,
            ),
          ] else if (_isDerived) ...[
            Text(
              'The gear this came from has been deleted, so its length is now '
              'fixed at what it was.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            DimensionField(
              controller: _length,
              label: 'Length of one',
              validator: _requiredNumber,
            ),
            const SizedBox(height: 8),
            Text(
              'How long one of these is. Measure it once and everything else '
              'can be described in them.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}

Future<CustomUnitDraft?> showCustomUnitSheet(
  BuildContext context, {
  required MeasurementUnit definitionUnit,
  CustomUnit? initial,
  GearItem? sourceItem,
}) {
  return showModalBottomSheet<CustomUnitDraft>(
    context: context,
    isScrollControlled: true,
    // Lengths in this sheet are always typed in the definition unit.
    builder: (context) => UnitScope(
      unit: definitionUnit,
      child: CustomUnitSheet(
        definitionUnit: definitionUnit,
        initial: initial,
        sourceItem: sourceItem,
      ),
    ),
  );
}

/// Prompts for a single line of text — used for naming a loadout.
///
/// The controller belongs to the dialog's own State rather than the caller.
/// Disposing it when the future completes would kill it while the route is
/// still animating out, and the field is still reading from it.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.label,
  });

  final String title;
  final String initial;
  final String label;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) =>
        _NameDialog(title: title, initial: initial, label: label),
  );
  return (name ?? '').isEmpty ? null : name;
}

/// Prompts for a single length, in [unit]. Returns the value in centimetres,
/// or null if cancelled. An empty field comes back as zero.
class _LengthDialog extends StatefulWidget {
  const _LengthDialog({
    required this.title,
    required this.label,
    required this.unit,
    required this.initial,
  });

  final String title;
  final String label;
  final MeasurementUnit unit;
  final double initial;

  @override
  State<_LengthDialog> createState() => _LengthDialogState();
}

class _LengthDialogState extends State<_LengthDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == 0 ? '' : widget.unit.format(widget.initial),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(0.0);
      return;
    }

    final centimetres = widget.unit.parseToCentimetres(text);
    Navigator.of(
      context,
    ).pop(centimetres == null || centimetres < 0 ? null : centimetres);
  }

  @override
  Widget build(BuildContext context) {
    return UnitScope(
      unit: widget.unit,
      child: AlertDialog(
        title: Text(widget.title),
        content: DimensionField(
          controller: _controller,
          label: widget.label,
          hint: '0',
          validator: (_) => null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}

Future<double?> showLengthDialog(
  BuildContext context, {
  required String title,
  required String label,
  required MeasurementUnit unit,
  double initial = 0,
}) {
  return showDialog<double>(
    context: context,
    builder: (context) =>
        _LengthDialog(title: title, label: label, unit: unit, initial: initial),
  );
}

// -------------------------------------------------------------------- plans

/// Names a plan, picks the bag it packs into, and sets its tolerance.
class PlanSheet extends StatefulWidget {
  const PlanSheet({
    super.key,
    required this.containers,
    this.initial,
    this.defaultTolerance = 0,
  });

  /// Library gear marked as holding other gear.
  final List<GearItem> containers;

  final PlanRecord? initial;

  /// Used for a new plan, in centimetres.
  final double defaultTolerance;

  @override
  State<PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<PlanSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _tolerance;
  late final TextEditingController _heightOverflow;
  String? _containerItemId;

  MeasurementUnit get _unit => UnitScope.of(context);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _tolerance = TextEditingController();
    _heightOverflow = TextEditingController();
    _containerItemId =
        widget.initial?.containerItemId ??
        (widget.containers.length == 1 ? widget.containers.single.id : null);
  }

  var _didFill = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didFill) return;
    _didFill = true;

    final tolerance = widget.initial?.tolerance ?? widget.defaultTolerance;
    if (tolerance > 0) _tolerance.text = _unit.format(tolerance);

    final heightOverflow = widget.initial?.heightOverflow ?? 0;
    if (heightOverflow > 0) {
      _heightOverflow.text = _unit.format(heightOverflow);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _tolerance.dispose();
    _heightOverflow.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final containerItemId = _containerItemId;
    if (containerItemId == null) return;

    final toleranceText = _tolerance.text.trim();
    final heightOverflowText = _heightOverflow.text.trim();
    Navigator.of(context).pop(
      PlanDraft(
        name: _name.text.trim(),
        containerItemId: containerItemId,
        tolerance: toleranceText.isEmpty
            ? 0
            : _unit.toCentimetres(double.parse(toleranceText)),
        heightOverflow: heightOverflowText.isEmpty
            ? 0
            : _unit.toCentimetres(double.parse(heightOverflowText)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: _SheetShell(
        title: widget.initial == null ? 'New plan' : 'Edit plan',
        children: [
          if (widget.containers.isEmpty)
            Text(
              'Nothing in your library holds gear yet. Add a bag, box or pouch '
              'and switch on "Holds other gear".',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else ...[
            TextFormField(
              controller: _name,
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Plan name',
                hintText: 'Overnight hike',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _containerItemId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Pack into',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final container in widget.containers)
                  DropdownMenuItem(
                    value: container.id,
                    child: Text(
                      '${container.name} · '
                      '${formatDimensions(_unit, width: container.width, height: container.height, depth: container.depth)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _containerItemId = value),
              validator: (value) => value == null ? 'Pick a container' : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Change this later to see the same kit in a different bag.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DimensionField(
              controller: _tolerance,
              label: 'Tolerance',
              hint: '0',
              validator: _optionalNonNegativeNumber,
            ),
            const SizedBox(height: 8),
            Text(
              'Gap kept clear of every wall and between any two pieces of '
              'gear. Leave empty to let things sit flush.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            DimensionField(
              controller: _heightOverflow,
              label: 'Open top',
              hint: '0',
              validator: _optionalNonNegativeNumber,
            ),
            const SizedBox(height: 8),
            Text(
              'How much higher gear may stick out above the container, for '
              'one with no lid to bump into. Leave empty to hold gear to '
              'the container\'s real height.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _submit, child: const Text('Save')),
          ],
        ],
      ),
    );
  }
}

Future<PlanDraft?> showPlanSheet(
  BuildContext context, {
  required List<GearItem> containers,
  PlanRecord? initial,
  double defaultTolerance = 0,
}) {
  final unit = UnitScope.of(context);
  return showModalBottomSheet<PlanDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => UnitScope(
      unit: unit,
      child: PlanSheet(
        containers: containers,
        initial: initial,
        defaultTolerance: defaultTolerance,
      ),
    ),
  );
}
