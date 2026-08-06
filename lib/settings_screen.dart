import 'package:flutter/material.dart';

import 'edit_sheets.dart';
import 'models.dart';
import 'store.dart';
import 'units.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final GearStore store;

  /// A custom unit's own length cannot be entered in itself, so lengths are
  /// defined in the current unit only when that is a built-in, and in
  /// centimetres otherwise.
  MeasurementUnit get _definitionUnit =>
      MeasurementUnit.builtInById(store.settings.unitId) ??
      MeasurementUnit.centimetres;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final current = store.unit;

        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Heading('Measure in'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final unit in store.availableUnits)
                      ChoiceChip(
                        label: Text(unit.symbol),
                        selected: unit.id == current.id,
                        onSelected: (_) => store.setUnitId(unit.id),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Measurements are stored in centimetres and converted for '
                  'display, so switching units never changes your gear.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              _Heading('Your own units'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Measure in whatever you actually carry. A unit made from a '
                  'piece of gear follows that gear, so correcting its size '
                  'recalibrates everything you measured with it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final custom in store.customUnits)
                _CustomUnitTile(
                  custom: custom,
                  resolved: store.resolveCustomUnit(custom),
                  sourceItem: store.sourceItemFor(custom),
                  definitionUnit: _definitionUnit,
                  onEdit: () => _editCustomUnit(context, custom),
                  onDelete: () => _deleteCustomUnit(context, custom),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addFreeFormUnit(context),
                        icon: const Icon(Icons.straighten),
                        label: const Text('From a length'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addUnitFromGear(context),
                        icon: const Icon(Icons.category_outlined),
                        label: const Text('From gear'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              _Heading('Default tolerance'),
              ListTile(
                title: Text(current.formatWithSymbol(
                  store.settings.defaultTolerance,
                )),
                subtitle: const Text(
                  'Given to new containers. Existing ones keep their own.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _editTolerance(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  'Tolerance is the gap kept clear of every container wall and '
                  'between any two pieces of gear. Zero lets things sit flush, '
                  'which fits on paper but rarely in the bag.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addFreeFormUnit(BuildContext context) async {
    final result = await showCustomUnitSheet(
      context,
      definitionUnit: _definitionUnit,
    );
    if (result == null) return;

    await store.addCustomUnit(
      name: result.name,
      centimetres: result.centimetres ?? 1,
    );
  }

  Future<void> _addUnitFromGear(BuildContext context) async {
    if (store.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add something to your gear library first.'),
        ),
      );
      return;
    }

    final itemId = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Measure with which gear?'),
              dense: true,
            ),
            const Divider(height: 1),
            for (final item in store.items)
              ListTile(
                title: Text(item.name),
                subtitle: Text(
                  formatDimensions(
                    _definitionUnit,
                    width: item.width,
                    height: item.height,
                    depth: item.depth,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(item.id),
              ),
          ],
        ),
      ),
    );
    if (itemId == null || !context.mounted) return;

    final item = store.itemById(itemId);
    if (item == null) return;

    final axis = await _pickAxis(context, item);
    if (axis == null) return;

    await store.addCustomUnitFromItem(itemId, axis: axis);
  }

  Future<GearAxis?> _pickAxis(BuildContext context, GearItem item) {
    return showModalBottomSheet<GearAxis>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Which side of the ${item.name}?'),
              dense: true,
            ),
            const Divider(height: 1),
            for (final axis in GearAxis.values)
              if (item.dimension(axis) != null)
                ListTile(
                  title: Text(axis.label),
                  subtitle: Text(
                    _definitionUnit.formatWithSymbol(item.dimension(axis)!),
                  ),
                  trailing: axis == item.longestAxis
                      ? const Chip(label: Text('longest'))
                      : null,
                  onTap: () => Navigator.of(context).pop(axis),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCustomUnit(BuildContext context, CustomUnit custom) async {
    final item = store.sourceItemFor(custom);

    final result = await showCustomUnitSheet(
      context,
      definitionUnit: _definitionUnit,
      initial: custom,
      sourceItem: item,
    );
    if (result == null) return;

    await store.updateCustomUnit(
      custom.id,
      name: result.name,
      centimetres: custom.isDerived ? null : result.centimetres,
      axis: result.axis,
    );
  }

  Future<void> _deleteCustomUnit(
    BuildContext context,
    CustomUnit custom,
  ) async {
    final inUse = store.settings.unitId == custom.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${custom.name}?'),
        content: Text(
          inUse
              ? "You're measuring in it right now, so this switches you back "
                    'to centimetres. Nothing you have measured changes.'
              : 'Nothing you have measured changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) await store.deleteCustomUnit(custom.id);
  }

  Future<void> _editTolerance(BuildContext context) async {
    final centimetres = await showLengthDialog(
      context,
      title: 'Default tolerance',
      label: 'Tolerance',
      unit: store.unit,
      initial: store.settings.defaultTolerance,
    );
    if (centimetres == null) return;

    await store.setDefaultTolerance(centimetres);
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _CustomUnitTile extends StatelessWidget {
  const _CustomUnitTile({
    required this.custom,
    required this.resolved,
    required this.sourceItem,
    required this.definitionUnit,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomUnit custom;
  final MeasurementUnit resolved;
  final GearItem? sourceItem;
  final MeasurementUnit definitionUnit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final length = definitionUnit.formatWithSymbol(
      resolved.centimetresPerUnit,
    );

    final source = switch ((custom.isDerived, sourceItem)) {
      (true, final item?) =>
        '$length · ${custom.sourceAxis?.label.toLowerCase()} of ${item.name}',
      // The gear it came from is gone, so it is stuck at the length it had.
      (true, null) => '$length · gear deleted, length fixed',
      _ => length,
    };

    return ListTile(
      leading: Icon(
        custom.isDerived ? Icons.category_outlined : Icons.straighten,
      ),
      title: Text(custom.name),
      subtitle: Text(source),
      onTap: onEdit,
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}
