import 'package:flutter/material.dart';

import 'edit_sheets.dart';
import 'gear_library_screen.dart';
import 'models.dart';
import 'store.dart';

/// Saved kits — a named set of gear you pack again and again.
class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key, required this.store});

  final GearStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Recipes')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _create(context),
            icon: const Icon(Icons.add),
            label: const Text('New recipe'),
          ),
          body: store.recipes.isEmpty
              ? const _EmptyRecipes()
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: store.recipes.length,
                  itemBuilder: (context, index) {
                    final recipe = store.recipes[index];
                    final names = recipe.itemIds
                        .map((id) => store.itemById(id)?.name)
                        .whereType<String>()
                        .toList();

                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: ListTile(
                        onTap: () => _edit(context, recipe),
                        title: Text(recipe.name),
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
                          onPressed: () => _delete(context, recipe),
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
      title: 'New recipe',
      label: 'Recipe name',
    );
    if (name == null || !context.mounted) return;

    final recipe = await store.addRecipe(name: name);
    if (!context.mounted) return;
    await _edit(context, recipe);
  }

  Future<void> _edit(BuildContext context, Recipe recipe) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RecipeDetailScreen(
          store: store,
          recipeId: recipe.id,
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Recipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${recipe.name}?'),
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

    if (confirmed ?? false) await store.deleteRecipe(recipe.id);
  }
}

/// Edits what is in one recipe.
class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({
    super.key,
    required this.store,
    required this.recipeId,
  });

  final GearStore store;
  final String recipeId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final recipe = store.recipeById(recipeId);
        if (recipe == null) {
          return const Scaffold(
            body: Center(child: Text('This recipe was deleted.')),
          );
        }

        final items = recipe.itemIds
            .map((id) => store.itemById(id))
            .whereType<GearItem>()
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(recipe.name),
            actions: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context, recipe),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _addGear(context, recipe),
            icon: const Icon(Icons.add),
            label: const Text('Add gear'),
          ),
          body: items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Nothing in this recipe yet. Add gear from your library.',
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
                      onPressed: () => _removeAt(recipe, index),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<void> _rename(BuildContext context, Recipe recipe) async {
    final name = await showNameDialog(
      context,
      title: 'Rename recipe',
      initial: recipe.name,
      label: 'Recipe name',
    );
    if (name == null) return;

    await store.updateRecipe(
      recipe.id,
      name: name,
      itemIds: recipe.itemIds,
    );
  }

  Future<void> _addGear(BuildContext context, Recipe recipe) async {
    final chosen = await showGearPicker(context, store);
    if (chosen == null || chosen.isEmpty) return;

    await store.updateRecipe(
      recipe.id,
      name: recipe.name,
      itemIds: [...recipe.itemIds, ...chosen],
    );
  }

  /// Removes by position, not by id — a recipe may list the same item twice.
  Future<void> _removeAt(Recipe recipe, int index) async {
    final itemIds = [...recipe.itemIds]..removeAt(index);
    await store.updateRecipe(
      recipe.id,
      name: recipe.name,
      itemIds: itemIds,
    );
  }
}

class _EmptyRecipes extends StatelessWidget {
  const _EmptyRecipes();

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
            Text('No recipes yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'A recipe is a named set of gear — "Overnight hike", "Summer '
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
