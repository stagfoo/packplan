import 'package:flutter/material.dart';

import 'diagram.dart';
import 'edit_sheets.dart';
import 'models.dart';
import 'store.dart';
import 'units.dart';

/// Filters a list of gear by tag and free text. Shared by the library screen
/// and the picker that adds gear to a container.
class GearFilter {
  const GearFilter({this.tags = const {}, this.query = ''});

  final Set<String> tags;
  final String query;

  bool get isEmpty => tags.isEmpty && query.trim().isEmpty;

  /// Gear must carry *every* selected tag, not just one — narrowing is what
  /// makes a tag filter useful once you have a few dozen items.
  bool matches(GearItem item) {
    if (!tags.every(item.tags.contains)) return false;

    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return item.name.toLowerCase().contains(needle) ||
        item.tags.any((tag) => tag.contains(needle));
  }

  GearFilter copyWith({Set<String>? tags, String? query}) =>
      GearFilter(tags: tags ?? this.tags, query: query ?? this.query);
}

/// Tag chips plus a search box.
class GearFilterBar extends StatefulWidget {
  const GearFilterBar({
    super.key,
    required this.filter,
    required this.allTags,
    required this.onChanged,
  });

  final GearFilter filter;
  final List<String> allTags;
  final ValueChanged<GearFilter> onChanged;

  @override
  State<GearFilterBar> createState() => _GearFilterBarState();
}

class _GearFilterBarState extends State<GearFilterBar> {
  // The controller has to outlive a rebuild, or every keystroke would reset
  // the cursor to the start of the field.
  late final TextEditingController _search = TextEditingController(
    text: widget.filter.query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    widget.onChanged(widget.filter.copyWith(query: ''));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search gear',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: widget.filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: _clear,
                    ),
            ),
            onChanged: (value) =>
                widget.onChanged(widget.filter.copyWith(query: value)),
          ),
        ),
        if (widget.allTags.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final tag in widget.allTags)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(tag),
                      selected: widget.filter.tags.contains(tag),
                      onSelected: (selected) => widget.onChanged(
                        widget.filter.copyWith(
                          tags: selected
                              ? <String>{...widget.filter.tags, tag}
                              : (<String>{...widget.filter.tags}..remove(tag)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A single gear row — colour swatch, name, dimensions and tags.
class GearTile extends StatelessWidget {
  const GearTile({
    super.key,
    required this.item,
    this.onTap,
    this.trailing,
    this.selected = false,
    this.subtitleSuffix,
  });

  final GearItem item;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool selected;
  final String? subtitleSuffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = UnitScope.of(context);

    final notes = <String>[
      formatDimensions(
        unit,
        width: item.width,
        height: item.height,
        depth: item.depth,
      ),
      if (item.tags.isNotEmpty) item.tags.map((tag) => '#$tag').join(' '),
      if (!item.rotatable) 'fixed orientation',
      if (subtitleSuffix != null) subtitleSuffix!,
    ];

    return ListTile(
      onTap: onTap,
      selected: selected,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: item.color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      title: Text(item.name),
      subtitle: Text(
        notes.join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing,
    );
  }
}

/// The gear catalogue: everything you own, defined once and reused.
class GearLibraryScreen extends StatefulWidget {
  const GearLibraryScreen({super.key, required this.store});

  final GearStore store;

  @override
  State<GearLibraryScreen> createState() => _GearLibraryScreenState();
}

class _GearLibraryScreenState extends State<GearLibraryScreen> {
  GearFilter _filter = const GearFilter();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final allTags = widget.store.allTags;
        final visible = widget.store.items
            .where(_filter.matches)
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return Scaffold(
          appBar: AppBar(title: const Text('Gear')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text('New gear'),
          ),
          body: Column(
            children: [
              GearFilterBar(
                filter: _filter,
                allTags: allTags,
                onChanged: (filter) => setState(() => _filter = filter),
              ),
              const Divider(height: 1),
              Expanded(
                child: widget.store.items.isEmpty
                    ? const _EmptyLibrary()
                    : visible.isEmpty
                    ? const Center(child: Text('Nothing matches that filter.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          final uses = widget.store.usageCount(item.id);
                          return GearTile(
                            item: item,
                            subtitleSuffix: uses == 0
                                ? null
                                : 'in $uses ${uses == 1 ? 'plan' : 'plans'}',
                            onTap: () => _editItem(item),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) => switch (value) {
                                'edit' => _editItem(item),
                                'unit' => _useAsUnit(item),
                                'delete' => _deleteItem(item, uses),
                                _ => null,
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                const PopupMenuItem(
                                  value: 'unit',
                                  child: Text('Measure with this'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addItem() async {
    final draft = await showGearItemSheet(
      context,
      knownTags: widget.store.allTags,
    );
    if (draft == null) return;

    await widget.store.addItem(
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
      rotatable: draft.rotatable,
      tags: draft.tags,
    );
  }

  Future<void> _editItem(GearItem item) async {
    final draft = await showGearItemSheet(
      context,
      initial: item,
      knownTags: widget.store.allTags,
    );
    if (draft == null) return;

    await widget.store.updateItem(
      item.id,
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
      rotatable: draft.rotatable,
      tags: draft.tags,
    );
  }

  /// Turns a piece of gear into a unit you can measure everything else in.
  Future<void> _useAsUnit(GearItem item) async {
    final axis = await showModalBottomSheet<GearAxis>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Measure with which side of the ${item.name}?'),
              dense: true,
            ),
            const Divider(height: 1),
            for (final axis in GearAxis.values)
              if (item.dimension(axis) != null)
                ListTile(
                  title: Text(axis.label),
                  subtitle: Text(
                    UnitScope.of(context).formatWithSymbol(
                      item.dimension(axis)!,
                    ),
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
    if (axis == null || !mounted) return;

    final unit = await widget.store.addCustomUnitFromItem(item.id, axis: axis);
    if (unit == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You can now measure in ${unit.name}.'),
        action: SnackBarAction(
          label: 'Use it',
          onPressed: () => widget.store.setUnitId(unit.id),
        ),
      ),
    );
  }

  Future<void> _deleteItem(GearItem item, int uses) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.name}?'),
        content: Text(
          uses == 0
              ? 'This cannot be undone.'
              : "It's in $uses ${uses == 1 ? 'plan' : 'plans'} and will be "
                    'removed from ${uses == 1 ? 'it' : 'them'} too. '
                    'This cannot be undone.',
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

    if (confirmed ?? false) await widget.store.deleteItem(item.id);
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.category_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No gear yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Measure something once here and you can drop it into any plan, '
              'as many times as you like.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks gear from the library to add to a container. Returns the chosen item
/// ids, in the order they were tapped.
class GearPickerSheet extends StatefulWidget {
  const GearPickerSheet({super.key, required this.store});

  final GearStore store;

  @override
  State<GearPickerSheet> createState() => _GearPickerSheetState();
}

class _GearPickerSheetState extends State<GearPickerSheet> {
  GearFilter _filter = const GearFilter();
  final List<String> _chosen = [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = widget.store.items.where(_filter.matches).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Add gear', style: theme.textTheme.titleLarge),
                ),
                TextButton.icon(
                  onPressed: _createAndChoose,
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                ),
              ],
            ),
          ),
          GearFilterBar(
            filter: _filter,
            allTags: widget.store.allTags,
            onChanged: (filter) => setState(() => _filter = filter),
          ),
          const Divider(height: 1),
          Flexible(
            child: widget.store.items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Your gear library is empty. Tap New to measure '
                      'something.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final count = _chosen
                          .where((id) => id == item.id)
                          .length;
                      return GearTile(
                        item: item,
                        selected: count > 0,
                        onTap: () => setState(() => _chosen.add(item.id)),
                        trailing: count == 0
                            ? const Icon(Icons.add_circle_outline)
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    onPressed: () => setState(
                                      () => _chosen.remove(item.id),
                                    ),
                                  ),
                                  Text('$count'),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () =>
                                        setState(() => _chosen.add(item.id)),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _chosen.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_chosen),
                    child: Text(
                      _chosen.isEmpty ? 'Add' : 'Add ${_chosen.length}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createAndChoose() async {
    final draft = await showGearItemSheet(
      context,
      knownTags: widget.store.allTags,
    );
    if (draft == null) return;

    final item = await widget.store.addItem(
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
      rotatable: draft.rotatable,
      tags: draft.tags,
    );
    setState(() => _chosen.add(item.id));
  }
}

/// Opens the picker. Returns the item ids chosen, or null if cancelled.
Future<List<String>?> showGearPicker(BuildContext context, GearStore store) {
  final unit = UnitScope.of(context);
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => UnitScope(
      unit: unit,
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) => GearPickerSheet(store: store),
      ),
    ),
  );
}
