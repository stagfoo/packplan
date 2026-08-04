import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/models.dart';
import 'package:packplan/repository.dart';
import 'package:packplan/store.dart';
import 'package:packplan/units.dart';

void main() {
  late Directory directory;
  late GearStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('packplan_test');
    store = GearStore(repository: GearRepository(directory: directory));
    await store.load();
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Future<GearStore> reload() async {
    final reloaded = GearStore(
      repository: GearRepository(directory: directory),
    );
    await reloaded.load();
    return reloaded;
  }

  Future<GearContainer> makePack({double? depth, double? tolerance}) =>
      store.addContainer(
        name: 'daypack',
        width: 30,
        height: 40,
        depth: depth,
        tolerance: tolerance,
      );

  Future<GearItem> makeMug() =>
      store.addItem(name: 'mug', width: 9, height: 9, tags: ['cook']);

  group('library', () {
    test('starts empty', () {
      expect(store.items, isEmpty);
      expect(store.containers, isEmpty);
      expect(store.recipes, isEmpty);
      expect(store.isLoaded, isTrue);
    });

    test('adding gear makes it retrievable', () async {
      final item = await makeMug();

      expect(store.items, hasLength(1));
      expect(store.itemById(item.id)!.name, 'mug');
    });

    test('gives new gear different colours', () async {
      final first = await makeMug();
      final second = await store.addItem(name: 'pot', width: 12, height: 12);

      expect(first.colorValue, isNot(second.colorValue));
    });

    test('normalises tags on the way in', () async {
      final item = await store.addItem(
        name: 'mug',
        width: 9,
        height: 9,
        tags: ['Cook', '#cook', ' EDC '],
      );

      expect(store.itemById(item.id)!.tags, ['cook', 'edc']);
    });

    test('collects every tag in use', () async {
      await store.addItem(name: 'mug', width: 9, height: 9, tags: ['cook']);
      await store.addItem(name: 'knife', width: 9, height: 3, tags: ['edc']);

      expect(store.allTags, ['cook', 'edc']);
    });

    test('the same gear can be used by two containers', () async {
      final pack = await makePack();
      final pouch = await store.addContainer(
        name: 'pouch',
        width: 20,
        height: 20,
      );
      final mug = await makeMug();

      await store.addGear(pack.id, mug.id);
      await store.addGear(pouch.id, mug.id);

      expect(store.usageCount(mug.id), 2);
      expect(store.planFor(pack.id)!.entries.single.item.name, 'mug');
      expect(store.planFor(pouch.id)!.entries.single.item.name, 'mug');
    });

    test('one container can hold two of the same thing', () async {
      final pack = await makePack();
      final mug = await makeMug();

      await store.addGear(pack.id, mug.id);
      await store.addGear(pack.id, mug.id);

      final plan = store.planFor(pack.id)!;
      expect(plan.entries, hasLength(2));
      expect(plan.packed, hasLength(2));
      // Two entries of the same item must not land on top of each other.
      final first = plan.entries[0].placement!;
      final second = plan.entries[1].placement!;
      expect(first.overlaps(second), isFalse);
    });

    test('resizing gear reseats it in every container that uses it', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);

      await store.updateItem(
        mug.id,
        name: 'mug',
        width: 20,
        height: 20,
        rotatable: true,
        tags: const [],
      );

      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.width, 20);
      expect(placement.height, 20);
    });

    test('renaming gear leaves placements alone', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final before = store.planFor(pack.id)!.entries.single.placement!;

      await store.updateItem(
        mug.id,
        name: 'titanium mug',
        width: 9,
        height: 9,
        rotatable: true,
        tags: const ['cook'],
      );

      final after = store.planFor(pack.id)!.entries.single;
      expect(after.item.name, 'titanium mug');
      expect(after.placement!.x, before.x);
      expect(after.placement!.y, before.y);
    });

    test('deleting gear removes it from containers and recipes', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final recipe = await store.addRecipe(name: 'kit', itemIds: [mug.id]);

      await store.deleteItem(mug.id);

      expect(store.items, isEmpty);
      expect(store.planFor(pack.id)!.entries, isEmpty);
      expect(store.containerById(pack.id)!.placements, isEmpty);
      expect(store.recipeById(recipe.id)!.itemIds, isEmpty);
    });
  });

  group('containers', () {
    test('deleting removes the container but keeps the gear', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);

      await store.deleteContainer(pack.id);

      expect(store.containers, isEmpty);
      expect(store.items, hasLength(1));
    });

    test('resizing re-packs so nothing is left hanging outside', () async {
      final pack = await makePack();
      final mat = await store.addItem(name: 'mat', width: 28, height: 30);
      await store.addGear(pack.id, mat.id);

      await store.updateContainer(
        pack.id,
        name: 'daypack',
        width: 20,
        height: 20,
        tolerance: 0,
      );

      expect(
        store.planFor(pack.id)!.unpacked.map((e) => e.item.name),
        ['mat'],
      );
    });

    test('raising the tolerance re-packs and can push gear out', () async {
      final pack = await makePack();
      final slab = await store.addItem(name: 'slab', width: 30, height: 40);
      await store.addGear(pack.id, slab.id);
      expect(store.planFor(pack.id)!.packed, hasLength(1));

      await store.updateContainer(
        pack.id,
        name: 'daypack',
        width: 30,
        height: 40,
        tolerance: 1,
      );

      // The slab exactly filled the pack, so any gap at all evicts it.
      expect(store.planFor(pack.id)!.unpacked, hasLength(1));
    });

    test('new containers inherit the default tolerance', () async {
      await store.setDefaultTolerance(1.5);
      final pack = await store.addContainer(
        name: 'pack',
        width: 30,
        height: 40,
      );

      expect(pack.tolerance, 1.5);
    });

    test('changing the default leaves existing containers alone', () async {
      final pack = await makePack(tolerance: 0);
      await store.setDefaultTolerance(2);

      expect(store.containerById(pack.id)!.tolerance, 0);
    });

    test('duplicating copies the gear and the layout', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final original = store.planFor(pack.id)!.entries.single.placement!;

      final copy = await store.duplicateContainer(pack.id);

      expect(copy!.name, 'daypack copy');
      final copied = store.planFor(copy.id)!.entries.single;
      expect(copied.item.id, mug.id);
      expect(copied.placement!.x, original.x);
      // Entries are fresh, so editing the copy cannot disturb the original.
      expect(copied.id, isNot(store.planFor(pack.id)!.entries.single.id));
    });

    test('removing an entry leaves the item in the library', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      await store.removeEntry(pack.id, entryId);

      expect(store.planFor(pack.id)!.entries, isEmpty);
      expect(store.items, hasLength(1));
    });
  });

  group('recipes', () {
    test('applying one adds all its gear', () async {
      final pack = await makePack();
      final mug = await makeMug();
      final stove = await store.addItem(name: 'stove', width: 12, height: 10);
      final recipe = await store.addRecipe(
        name: 'cook kit',
        itemIds: [mug.id, stove.id],
      );

      final unfitted = await store.applyRecipe(pack.id, recipe.id);

      expect(unfitted, isEmpty);
      expect(
        store.planFor(pack.id)!.entries.map((e) => e.item.name),
        ['mug', 'stove'],
      );
    });

    test('reports gear that found no room', () async {
      final pack = await store.addContainer(
        name: 'tiny',
        width: 10,
        height: 10,
      );
      final mug = await makeMug();
      final tent = await store.addItem(name: 'tent', width: 200, height: 200);
      final recipe = await store.addRecipe(
        name: 'kit',
        itemIds: [mug.id, tent.id],
      );

      final unfitted = await store.applyRecipe(pack.id, recipe.id);

      expect(unfitted.map((i) => i.name), ['tent']);
      // It is still added to the container, just not placed.
      expect(store.planFor(pack.id)!.entries, hasLength(2));
    });

    test('applying twice packs two of everything', () async {
      final pack = await makePack();
      final mug = await makeMug();
      final recipe = await store.addRecipe(name: 'kit', itemIds: [mug.id]);

      await store.applyRecipe(pack.id, recipe.id);
      await store.applyRecipe(pack.id, recipe.id);

      expect(store.planFor(pack.id)!.entries, hasLength(2));
    });

    test('a container can be saved as a recipe', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      await store.addGear(pack.id, mug.id);

      final recipe = await store.saveContainerAsRecipe(
        pack.id,
        name: 'my kit',
      );

      // Two entries of the same item means "pack two of these".
      expect(recipe.itemIds, [mug.id, mug.id]);
    });

    test('deleting a recipe keeps the gear', () async {
      final mug = await makeMug();
      final recipe = await store.addRecipe(name: 'kit', itemIds: [mug.id]);

      await store.deleteRecipe(recipe.id);

      expect(store.recipes, isEmpty);
      expect(store.items, hasLength(1));
    });
  });

  group('moving', () {
    test('a drag shifts gear and snaps to the grid', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dx: 5.3, dy: 2.2);

      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.x, 5.5);
      expect(placement.y, 2.0);
    });

    test('gear cannot be dragged out of the container', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dx: 500, dy: 500);

      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.right, lessThanOrEqualTo(30));
      expect(placement.bottom, lessThanOrEqualTo(40));
    });

    test('a drag stops at the tolerance margin, not the wall', () async {
      final pack = await makePack(tolerance: 2);
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dx: -500, dy: -500);

      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.x, 2);
      expect(placement.y, 2);
    });

    test('depth is fixed at zero in a flat plan', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dz: 10);

      expect(store.planFor(pack.id)!.entries.single.placement!.z, 0);
    });

    test('depth can be dragged in a 3D plan', () async {
      final pack = await makePack(depth: 20);
      final pot = await store.addItem(
        name: 'pot',
        width: 10,
        height: 10,
        depth: 5,
      );
      await store.addGear(pack.id, pot.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dz: 8);

      expect(store.planFor(pack.id)!.entries.single.placement!.z, 8);
    });
  });

  group('auto-pack', () {
    test('reports what did not fit', () async {
      final pack = await makePack();
      final mug = await makeMug();
      final tent = await store.addItem(name: 'tent', width: 200, height: 200);
      await store.addGear(pack.id, mug.id);
      await store.addGear(pack.id, tent.id);

      final result = await store.autoPack(pack.id);

      expect(result.everythingFits, isFalse);
      expect(result.unfitted.map((e) => e.item.name), ['tent']);
    });

    test('discards manual positions', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dx: 15, dy: 15);
      await store.autoPack(pack.id);

      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.x, 0);
      expect(placement.y, 0);
    });

    test('adding gear later leaves earlier positions alone', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;
      store.moveGear(pack.id, entryId, dx: 15, dy: 15);

      final stove = await store.addItem(name: 'stove', width: 12, height: 10);
      await store.addGear(pack.id, stove.id);

      final moved = store
          .planFor(pack.id)!
          .entries
          .firstWhere((e) => e.id == entryId)
          .placement!;
      expect(moved.x, 15);
      expect(moved.y, 15);
    });
  });

  group('settings', () {
    test('the unit choice survives a reload', () async {
      await store.setUnit(MeasurementUnit.inches);

      expect((await reload()).unit, MeasurementUnit.inches);
    });

    test('the default tolerance survives a reload', () async {
      await store.setDefaultTolerance(1.5);

      expect((await reload()).settings.defaultTolerance, 1.5);
    });
  });

  group('persistence', () {
    test('everything survives a reload', () async {
      final pack = await makePack(depth: 20, tolerance: 1);
      final pot = await store.addItem(
        name: 'pot',
        width: 10,
        height: 10,
        depth: 8,
        tags: ['cook'],
        rotatable: false,
      );
      await store.addGear(pack.id, pot.id);
      await store.addRecipe(name: 'cook kit', itemIds: [pot.id]);

      final reloaded = await reload();

      final item = reloaded.itemById(pot.id)!;
      expect(item.name, 'pot');
      expect(item.depth, 8);
      expect(item.tags, ['cook']);
      expect(item.rotatable, isFalse);

      final container = reloaded.containerById(pack.id)!;
      expect(container.depth, 20);
      expect(container.tolerance, 1);

      final plan = reloaded.planFor(pack.id)!;
      expect(plan.packed, hasLength(1));
      expect(reloaded.recipes.single.itemIds, [pot.id]);
    });

    test('drag positions are written out on flush', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dx: 10, dy: 10);
      await store.flush();

      final reloaded = await reload();
      expect(
        reloaded.planFor(pack.id)!.entries.single.placement!.x,
        10,
      );
    });

    test('a corrupt file does not stop the app starting', () async {
      await File('${directory.path}/packplan.json').writeAsString('not json');

      final recovered = await reload();

      expect(recovered.containers, isEmpty);
      expect(recovered.isLoaded, isTrue);
    });
  });

  group('migration from the container-owned schema', () {
    test('lifts old goods into the library and keeps placements', () async {
      // Exactly what version 1 wrote.
      await File('${directory.path}/packplan.json').writeAsString(
        jsonEncode({
          'containers': [
            {
              'id': 'container-1',
              'name': 'daypack',
              'width': 30.0,
              'height': 40.0,
              'depth': 20.0,
              'colorValue': kGearPalette.first,
              'goods': [
                {
                  'id': 'good-1',
                  'name': 'mug',
                  'width': 9.0,
                  'height': 9.0,
                  'depth': 9.0,
                  'colorValue': kGearPalette[1],
                  'rotatable': true,
                },
              ],
              'placements': {
                'good-1': {
                  'goodId': 'good-1',
                  'x': 3.0,
                  'y': 4.0,
                  'z': 5.0,
                  'width': 9.0,
                  'height': 9.0,
                  'depth': 9.0,
                },
              },
            },
          ],
        }),
      );

      final migrated = await reload();

      expect(migrated.items.single.name, 'mug');
      expect(migrated.items.single.tags, isEmpty);

      final plan = migrated.planFor('container-1')!;
      expect(plan.container.tolerance, 0);
      expect(plan.entries, hasLength(1));

      final placement = plan.entries.single.placement!;
      expect(placement.x, 3);
      expect(placement.y, 4);
      expect(placement.z, 5);
      // The placement must be re-keyed to the new entry id.
      expect(placement.entryId, plan.entries.single.id);
    });

    test('a migrated file is written back in the new shape', () async {
      await File('${directory.path}/packplan.json').writeAsString(
        jsonEncode({
          'containers': [
            {
              'id': 'container-1',
              'name': 'daypack',
              'width': 30.0,
              'height': 40.0,
              'colorValue': kGearPalette.first,
              'goods': [
                {
                  'id': 'good-1',
                  'name': 'mug',
                  'width': 9.0,
                  'height': 9.0,
                  'colorValue': kGearPalette[1],
                  'rotatable': true,
                },
              ],
              'placements': <String, dynamic>{},
            },
          ],
        }),
      );

      final migrated = await reload();
      await migrated.flush();

      final json =
          jsonDecode(
                await File('${directory.path}/packplan.json').readAsString(),
              )
              as Map<String, dynamic>;

      expect(json['version'], kSchemaVersion);
      expect(json['items'], hasLength(1));
      expect((json['containers'] as List).single['goods'], isNull);

      // And it still loads cleanly the second time round.
      expect((await reload()).items, hasLength(1));
    });

    test('an empty version 1 file migrates to nothing', () async {
      await File(
        '${directory.path}/packplan.json',
      ).writeAsString(jsonEncode({'containers': <dynamic>[]}));

      final migrated = await reload();

      expect(migrated.items, isEmpty);
      expect(migrated.containers, isEmpty);
    });
  });

  group('custom units', () {
    test('a free-form unit becomes selectable', () async {
      final hand = await store.addCustomUnit(name: 'hand', centimetres: 19);
      await store.setUnitId(hand.id);

      expect(store.unit.symbol, 'hand');
      expect(store.unit.format(38), '2');
    });

    test('a unit made from gear measures by its longest side', () async {
      final notebook = await store.addItem(
        name: 'notebook',
        width: 9,
        height: 21,
      );

      final unit = await store.addCustomUnitFromItem(notebook.id);

      expect(unit!.sourceAxis, GearAxis.height);
      expect(store.resolveCustomUnit(unit).centimetresPerUnit, 21);
    });

    test('a unit made from gear can measure by a chosen side', () async {
      final notebook = await store.addItem(
        name: 'notebook',
        width: 9,
        height: 21,
      );

      final unit = await store.addCustomUnitFromItem(
        notebook.id,
        axis: GearAxis.width,
      );

      expect(store.resolveCustomUnit(unit!).centimetresPerUnit, 9);
    });

    test('re-measuring the gear recalibrates the unit', () async {
      final notebook = await store.addItem(
        name: 'notebook',
        width: 9,
        height: 21,
      );
      final unit = await store.addCustomUnitFromItem(
        notebook.id,
        axis: GearAxis.height,
      );
      await store.setUnitId(unit!.id);
      expect(store.unit.format(42), '2');

      await store.updateItem(
        notebook.id,
        name: 'notebook',
        width: 9,
        height: 20,
        rotatable: true,
        tags: const [],
      );

      expect(store.unit.centimetresPerUnit, 20);
      expect(store.unit.format(40), '2');
    });

    test('deleting the source gear freezes the unit at its last length',
        () async {
      final notebook = await store.addItem(
        name: 'notebook',
        width: 9,
        height: 21,
      );
      final unit = await store.addCustomUnitFromItem(
        notebook.id,
        axis: GearAxis.height,
      );
      await store.setUnitId(unit!.id);

      await store.deleteItem(notebook.id);

      // The unit survives rather than vanishing mid-measurement.
      expect(store.unit.centimetresPerUnit, 21);
      expect(store.customUnits, hasLength(1));
    });

    test('gear with no depth cannot be a depth unit', () async {
      final map = await store.addItem(name: 'map', width: 20, height: 14);

      expect(
        await store.addCustomUnitFromItem(map.id, axis: GearAxis.depth),
        isNull,
      );
    });

    test('deleting the unit in use falls back to centimetres', () async {
      final hand = await store.addCustomUnit(name: 'hand', centimetres: 19);
      await store.setUnitId(hand.id);

      await store.deleteCustomUnit(hand.id);

      expect(store.unit, MeasurementUnit.centimetres);
      expect(store.customUnits, isEmpty);
    });

    test('a unit that no longer exists falls back to centimetres', () async {
      await store.setUnitId('ghost-unit');

      expect(store.unit, MeasurementUnit.centimetres);
    });

    test('a zero length is clamped so measurements stay finite', () async {
      final broken = await store.addCustomUnit(name: 'nothing', centimetres: 0);

      expect(
        store.resolveCustomUnit(broken).centimetresPerUnit,
        greaterThanOrEqualTo(kMinimumUnitLength),
      );
    });

    test('renaming a derived unit keeps it tracking its gear', () async {
      final notebook = await store.addItem(
        name: 'notebook',
        width: 9,
        height: 21,
      );
      final unit = await store.addCustomUnitFromItem(notebook.id);

      await store.updateCustomUnit(unit!.id, name: 'pad');

      final updated = store.customUnitById(unit.id)!;
      expect(updated.name, 'pad');
      expect(updated.sourceItemId, notebook.id);
      expect(store.resolveCustomUnit(updated).centimetresPerUnit, 21);
    });

    test('available units list built-ins first, then custom ones', () async {
      await store.addCustomUnit(name: 'hand', centimetres: 19);

      final ids = store.availableUnits.map((u) => u.symbol).toList();
      expect(ids.take(3), ['cm', 'mm', 'in']);
      expect(ids.last, 'hand');
    });

    test('custom units survive a reload', () async {
      final notebook = await store.addItem(
        name: 'notebook',
        width: 9,
        height: 21,
      );
      final derived = await store.addCustomUnitFromItem(notebook.id);
      await store.addCustomUnit(name: 'hand', centimetres: 19);
      await store.setUnitId(derived!.id);

      final reloaded = await reload();

      expect(reloaded.customUnits, hasLength(2));
      expect(reloaded.unit.symbol, 'notebook');
      expect(reloaded.unit.centimetresPerUnit, 21);
      expect(reloaded.customUnitById(derived.id)!.sourceAxis, GearAxis.height);
    });
  });
}
