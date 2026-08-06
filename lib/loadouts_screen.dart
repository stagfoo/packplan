import 'package:flutter/material.dart';

import 'edit_sheets.dart';
import 'gear_library_screen.dart';
import 'models.dart';
import 'store.dart';

/// Saved kits — a named set of gear you pack again and again.
class LoadoutsScreen extends StatelessWidget {
  const LoadoutsScreen({super.key, required this.store});

  final GearStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Loadouts')),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab-loadouts',
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('New loadout'),
          ),
          body: store.loadouts.isEmpty
              ? const _EmptyLoadouts()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: store.loadouts.length,
                  itemBuilder: (context, index) {
                    final loadout = store.loadouts[index];
                    final names = loadout.itemIds
                        .map((id) => store.itemById(id)?.name)
                        .whereType<String>()
                        .toList();

                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: ListTile(
                        onTap: () => _edit(context, loadout),
                        title: Text(loadout.name),
                        subtitle: Text(
                          names.isEmpty
                              ? 'Empty'
                              : '${names.length} '
                                    '${names.length == 1 ? 'item' : 'items'} · '
                                    '${names.join(', ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, loadout),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = await showNameDialog(
      context,
      title: 'New loadout',
      label: 'Loadout name',
    );
    if (name == null || !context.mounted) return;

    final loadout = await store.addLoadout(name: name);
    if (!context.mounted) return;
    await _edit(context, loadout);
  }

  Future<void> _edit(BuildContext context, Loadout loadout) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => LoadoutDetailScreen(
          store: store,
          loadoutId: loadout.id,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Loadout loadout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${loadout.name}?'),
        content: const Text(
          'The gear itself stays in your library. This cannot be undone.',
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

    if (confirmed ?? false) await store.deleteLoadout(loadout.id);
  }
}

/// Edits what is in one loadout.
class LoadoutDetailScreen extends StatelessWidget {
  const LoadoutDetailScreen({
    super.key,
    required this.store,
    required this.loadoutId,
  });

  final GearStore store;
  final String loadoutId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final loadout = store.loadoutById(loadoutId);
        if (loadout == null) {
          return const Scaffold(
            body: Center(child: Text('This loadout was deleted.')),
          );
        }

        final items = loadout.itemIds
            .map((id) => store.itemById(id))
            .whereType<GearItem>()
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(loadout.name),
            actions: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context, loadout),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'fab-loadout-detail',
            onPressed: () => _addGear(context, loadout),
            icon: const Icon(Icons.add),
            label: const Text('Add gear'),
          ),
          body: items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nothing in this loadout yet. Add gear from your library.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length,
                  itemBuilder: (context, index) => GearTile(
                    item: items[index],
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => _removeAt(loadout, index),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _rename(BuildContext context, Loadout loadout) async {
    final name = await showNameDialog(
      context,
      title: 'Rename loadout',
      initial: loadout.name,
      label: 'Loadout name',
    );
    if (name == null) return;

    await store.updateLoadout(
      loadout.id,
      name: name,
      itemIds: loadout.itemIds,
    );
  }

  Future<void> _addGear(BuildContext context, Loadout loadout) async {
    final chosen = await showGearPicker(context, store);
    if (chosen == null || chosen.isEmpty) return;

    await store.updateLoadout(
      loadout.id,
      name: loadout.name,
      itemIds: [...loadout.itemIds, ...chosen],
    );
  }

  /// Removes by position, not by id — a loadout may list the same item twice.
  Future<void> _removeAt(Loadout loadout, int index) async {
    final itemIds = [...loadout.itemIds]..removeAt(index);
    await store.updateLoadout(
      loadout.id,
      name: loadout.name,
      itemIds: itemIds,
    );
  }
}

class _EmptyLoadouts extends StatelessWidget {
  const _EmptyLoadouts();

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
              Icons.checklist_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No loadouts yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'A loadout is a named set of gear — "Overnight hike", "Summer '
              'minimal" — that you can drop into any container in one go.',
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
