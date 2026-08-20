import 'package:flutter/material.dart';

import 'diagram.dart';
import 'edit_sheets.dart';
import 'models.dart';
import 'plan_detail_screen.dart';
import 'settings_screen.dart';
import 'store.dart';
import 'units.dart';

/// The plans tab: every container-plus-gear combination you have set up.
class PlanListScreen extends StatelessWidget {
  const PlanListScreen({super.key, required this.store});

  final GearStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final plans = store.plans;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Plans'),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => SettingsScreen(store: store),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            // All three tabs stay alive in an IndexedStack, so their buttons
            // share a Hero tag unless each is given its own.
            heroTag: 'fab-plans',
            onPressed: () => _addPlan(context),
            icon: const Icon(Icons.add),
            label: const Text('New plan'),
          ),
          body: !store.isLoaded
              ? const Center(child: CircularProgressIndicator())
              : store.loadError != null
              ? _LoadFailed(error: store.loadError!, onRetry: store.load)
              : plans.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: plans.length,
                  itemBuilder: (context, index) {
                    final plan = plans[index];
                    return _PlanTile(
                      plan: plan,
                      onOpen: () => _open(context, plan.id),
                      onDuplicate: () => store.duplicatePlan(plan.id),
                      onDelete: () => _confirmDelete(context, plan),
                    );
                  },
                ),
        );
      },
    );
  }

  void _open(BuildContext context, String planId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlanDetailScreen(store: store, planId: planId),
      ),
    );
  }

  Future<void> _addPlan(BuildContext context) async {
    final containers = store.containerItems;

    if (containers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add a bag to your gear first, with "Holds other gear" switched '
            'on.',
          ),
        ),
      );
      return;
    }

    final draft = await showPlanSheet(
      context,
      containers: containers,
      defaultTolerance: store.settings.defaultTolerance,
    );
    if (draft == null) return;

    final plan = await store.addPlan(
      containerItemId: draft.containerItemId,
      name: draft.name,
      tolerance: draft.tolerance,
      heightOverflow: draft.heightOverflow,
    );

    if (plan == null || !context.mounted) return;
    _open(context, plan.id);
  }

  Future<void> _confirmDelete(BuildContext context, Plan plan) async {
    final count = plan.entries.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${plan.name}?'),
        content: Text(
          count == 0
              ? 'The container stays in your gear. This cannot be undone.'
              : 'The container and the $count '
                    '${count == 1 ? 'piece' : 'pieces'} of gear in it stay in '
                    'your library. This cannot be undone.',
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

    if (confirmed ?? false) await store.deletePlan(plan.id);
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Plan plan;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = UnitScope.of(context);
    final container = plan.container;
    final unpacked = plan.unpacked.length;

    final fill = plan.volumeUsed ?? plan.areaUsed;
    final count = plan.entries.length;

    final notes = <String>[
      // The plan can be named anything, so say which bag it actually packs.
      container.name,
      formatDimensions(
        unit,
        width: container.width,
        height: container.height,
        depth: container.depth,
      ),
      '$count ${count == 1 ? 'item' : 'items'}',
      '${(fill * 100).round()}% full',
      if (plan.tolerance > 0)
        '${unit.formatWithSymbol(plan.tolerance)} tolerance',
      if (unpacked > 0) '$unpacked not packed',
    ];

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
        title: Text(plan.name),
        subtitle: Text(
          notes.join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(
            color: unpacked > 0
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => switch (value) {
            'duplicate' => onDuplicate(),
            'delete' => onDelete(),
            _ => null,
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

/// Shown when the saved data could not be read. Anything the user does from
/// here would overwrite whatever is on disk, so it says so plainly and offers
/// a retry rather than quietly starting fresh.
class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              "Couldn't load your gear",
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your saved data is still on disk. Adding anything now would '
              'replace it, so try again first.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
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
              'A plan is one container plus the gear you want in it. Add a '
              'pack, a dry bag or a pocket to your gear first — anything with '
              '"Holds other gear" switched on can be planned around.',
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
