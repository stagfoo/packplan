import 'package:flutter/material.dart';

import 'container_detail_screen.dart';
import 'diagram.dart';
import 'edit_sheets.dart';
import 'models.dart';
import 'store.dart';

/// The home screen: every container you have planned.
class ContainerListScreen extends StatelessWidget {
  const ContainerListScreen({super.key, required this.store});

  final GearStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('PackPlan')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addContainer(context),
            icon: const Icon(Icons.add),
            label: const Text('New container'),
          ),
          body: !store.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : store.containers.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: store.containers.length,
                  itemBuilder: (context, index) => _ContainerTile(
                    container: store.containers[index],
                    onOpen: () =>
                        _open(context, store.containers[index]),
                    onDelete: () =>
                        _confirmDelete(context, store.containers[index]),
                  ),
                ),
        );
      },
    );
  }

  void _open(BuildContext context, GearContainer container) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ContainerDetailScreen(
          store: store,
          containerId: container.id,
        ),
      ),
    );
  }

  Future<void> _addContainer(BuildContext context) async {
    final draft = await showGearEditSheet(
      context,
      title: 'New container',
      nameLabel: 'Container name',
    );
    if (draft == null) return;

    final container = await store.addContainer(
      name: draft.name,
      width: draft.width,
      height: draft.height,
      depth: draft.depth,
    );

    if (!context.mounted) return;
    _open(context, container);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    GearContainer container,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${container.name}?'),
        content: Text(
          container.goods.isEmpty
              ? 'This cannot be undone.'
              : 'Its ${container.goods.length} pieces of gear go with it. '
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

    if (confirmed ?? false) await store.deleteContainer(container.id);
  }
}

class _ContainerTile extends StatelessWidget {
  const _ContainerTile({
    required this.container,
    required this.onOpen,
    required this.onDelete,
  });

  final GearContainer container;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unpacked = container.unpackedGoods.length;

    final dimensions = [
      formatLength(container.width),
      formatLength(container.height),
      if (container.depth != null) formatLength(container.depth!),
    ].join(' × ');

    final volumeUsed = container.volumeUsed;
    final fill = volumeUsed ?? container.areaUsed;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: container.color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: container.color, width: 2),
          ),
          child: Icon(Icons.backpack_outlined, color: container.color),
        ),
        title: Text(container.name),
        subtitle: Text(
          '$dimensions cm · ${container.goods.length} '
          '${container.goods.length == 1 ? 'item' : 'items'} · '
          '${(fill * 100).round()}% full'
          '${unpacked > 0 ? ' · $unpacked not packed' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: unpacked > 0
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              Icons.backpack_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Nothing planned yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add a pack, a dry bag or a pocket, then fill it with gear to '
              'see what fits.',
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
