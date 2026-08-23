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

  /// A container in the library plus a plan built around it — what used to be
  /// a single "container" is now those two things.
  Future<PlanRecord> makePack({
    double? depth,
    double? tolerance,
    double heightOverflow = 0,
  }) async {
    final bag = await store.addItem(
      name: 'daypack',
      width: 30,
      height: 40,
      depth: depth,
      isContainer: true,
    );
    return (await store.addPlan(
      containerItemId: bag.id,
      name: 'daypack',
      tolerance: tolerance,
      heightOverflow: heightOverflow,
    ))!;
  }

  Future<GearItem> makeMug() =>
      store.addItem(name: 'mug', width: 9, height: 9, tags: ['cook']);

  group('library', () {
    test('starts empty', () {
      expect(store.items, isEmpty);
      expect(store.planRecords, isEmpty);
      expect(store.loadouts, isEmpty);
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

    test('the same gear can be used by two plans', () async {
      final pack = await makePack();
      final pouchBag = await store.addItem(
        name: 'pouch',
        width: 20,
        height: 20,
        isContainer: true,
      );
      final pouch = (await store.addPlan(containerItemId: pouchBag.id))!;
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

    test('deleting gear removes it from containers and loadouts', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final loadout = await store.addLoadout(name: 'kit', itemIds: [mug.id]);

      await store.deleteItem(mug.id);

      // The daypack itself is a library item too, and stays.
      expect(store.items.map((i) => i.name), ['daypack']);
      expect(store.planFor(pack.id)!.entries, isEmpty);
      expect(store.planRecordById(pack.id)!.placements, isEmpty);
      expect(store.loadoutById(loadout.id)!.itemIds, isEmpty);
    });
  });

  group('library export/import', () {
    test('exports a JSON snapshot of the library', () async {
      await store.addItem(name: 'mug', width: 9, height: 9, tags: ['cook']);

      final decoded = jsonDecode(store.exportLibraryJson());

      expect(decoded['kind'], 'packplan-library');
      expect(decoded['version'], kLibraryExportVersion);
      expect((decoded['items'] as List).single['name'], 'mug');
    });

    test('imports items an export produced', () async {
      await store.addItem(
        name: 'mug',
        width: 9,
        height: 9,
        depth: 5,
        tags: ['cook'],
      );
      final json = store.exportLibraryJson();

      final other = GearStore(
        repository: GearRepository(
          directory: await Directory.systemTemp.createTemp('packplan_import'),
        ),
      );
      await other.load();

      final outcome = await other.importLibraryJson(json);

      expect(outcome.added, 1);
      expect(outcome.skipped, 0);
      final imported = other.items.single;
      expect(imported.name, 'mug');
      expect(imported.width, 9);
      expect(imported.depth, 5);
      expect(imported.tags, ['cook']);
    });

    test('gives every imported item a fresh id', () async {
      final original = await store.addItem(name: 'mug', width: 9, height: 9);
      final json = store.exportLibraryJson();

      final other = GearStore(
        repository: GearRepository(
          directory: await Directory.systemTemp.createTemp('packplan_import'),
        ),
      );
      await other.load();
      await other.importLibraryJson(json);

      expect(other.items.single.id, isNot(original.id));
    });

    test('skips items already in the library by name', () async {
      await store.addItem(name: 'mug', width: 9, height: 9);
      final json = store.exportLibraryJson();

      // Importing its own export back into itself should not duplicate
      // anything.
      final outcome = await store.importLibraryJson(json);

      expect(outcome.added, 0);
      expect(outcome.skipped, 1);
      expect(store.items, hasLength(1));
    });

    test('a name match is case-insensitive', () async {
      await store.addItem(name: 'Mug', width: 9, height: 9);
      final json = store.exportLibraryJson();

      final other = GearStore(
        repository: GearRepository(
          directory: await Directory.systemTemp.createTemp('packplan_import'),
        ),
      );
      await other.load();
      await other.addItem(name: 'mug', width: 1, height: 1);

      final outcome = await other.importLibraryJson(json);

      expect(outcome.added, 0);
      expect(outcome.skipped, 1);
      expect(other.items, hasLength(1));
    });

    test('rejects a file that is not a library export', () async {
      expect(
        store.importLibraryJson('{"not": "a library"}'),
        throwsFormatException,
      );
      expect(store.importLibraryJson('not even json'), throwsFormatException);
    });
  });

  group('containers', () {
    test('deleting a plan keeps the container and the gear', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);

      await store.deletePlan(pack.id);

      expect(store.planRecords, isEmpty);
      expect(store.items.map((i) => i.name), ['daypack', 'mug']);
    });

    test('deleting the container gear deletes the plans built on it', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final bagId = store.planRecordById(pack.id)!.containerItemId;

      expect(store.plansBuiltOn(bagId), hasLength(1));
      await store.deleteItem(bagId);

      // A plan with nothing to pack into is meaningless.
      expect(store.planRecords, isEmpty);
      expect(store.items.map((i) => i.name), ['mug']);
    });

    test('a container can be packed inside another plan as gear', () async {
      final pack = await makePack();
      final pouch = await store.addItem(
        name: 'pouch',
        width: 12,
        height: 8,
        isContainer: true,
      );

      expect(await store.addGear(pack.id, pouch.id), isTrue);
      expect(
        store.planFor(pack.id)!.entries.single.item.name,
        'pouch',
      );
    });

    test('shrinking the container re-packs every plan using it', () async {
      final pack = await makePack();
      final mat = await store.addItem(name: 'mat', width: 28, height: 30);
      await store.addGear(pack.id, mat.id);
      expect(store.planFor(pack.id)!.packed, hasLength(1));

      final bagId = store.planRecordById(pack.id)!.containerItemId;
      await store.updateItem(
        bagId,
        name: 'daypack',
        width: 20,
        height: 20,
        rotatable: true,
        tags: const [],
        isContainer: true,
      );

      expect(
        store.planFor(pack.id)!.unpacked.map((e) => e.item.name),
        ['mat'],
      );
    });

    test('swapping the container re-packs into the new one', () async {
      final pack = await makePack();
      final mat = await store.addItem(name: 'mat', width: 28, height: 30);
      await store.addGear(pack.id, mat.id);

      final tiny = await store.addItem(
        name: 'tiny',
        width: 10,
        height: 10,
        isContainer: true,
      );
      await store.updatePlan(
        pack.id,
        name: 'daypack',
        containerItemId: tiny.id,
        tolerance: 0,
      );

      expect(store.planFor(pack.id)!.container.name, 'tiny');
      expect(store.planFor(pack.id)!.unpacked, hasLength(1));
    });

    test('raising the tolerance re-packs and can push gear out', () async {
      final pack = await makePack();
      final slab = await store.addItem(name: 'slab', width: 30, height: 40);
      await store.addGear(pack.id, slab.id);
      expect(store.planFor(pack.id)!.packed, hasLength(1));

      await store.updatePlan(pack.id, name: 'daypack', tolerance: 1);

      // The slab exactly filled the pack, so any gap at all evicts it.
      expect(store.planFor(pack.id)!.unpacked, hasLength(1));
    });

    test('changing the height overflow does not re-pack', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;
      store.moveGear(pack.id, entryId, dx: 5, dy: 5);
      await store.flush();
      final beforeChange = store.planFor(pack.id)!.entries.single.placement!;

      // A change that only relaxes how high gear may be dragged should never
      // undo a manual layout the way a real reshape (tolerance, container)
      // does.
      await store.updatePlan(
        pack.id,
        name: 'daypack',
        tolerance: 0,
        heightOverflow: 10,
      );

      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.x, beforeChange.x);
      expect(placement.y, beforeChange.y);
      expect(store.planRecordById(pack.id)!.heightOverflow, 10);
    });

    test('new plans inherit the default tolerance', () async {
      await store.setDefaultTolerance(1.5);
      final bag = await store.addItem(
        name: 'pack',
        width: 30,
        height: 40,
        isContainer: true,
      );
      final plan = await store.addPlan(containerItemId: bag.id);

      expect(plan!.tolerance, 1.5);
    });

    test('a plan cannot be built on gear that is not in the library', () async {
      expect(await store.addPlan(containerItemId: 'ghost'), isNull);
    });

    test('a plan takes its name from its container by default', () async {
      final bag = await store.addItem(
        name: 'dry bag',
        width: 30,
        height: 40,
        isContainer: true,
      );
      final plan = await store.addPlan(containerItemId: bag.id);

      expect(plan!.name, 'dry bag');
    });

    test('changing the default leaves existing containers alone', () async {
      final pack = await makePack(tolerance: 0);
      await store.setDefaultTolerance(2);

      expect(store.planRecordById(pack.id)!.tolerance, 0);
    });

    test('duplicating copies the height overflow', () async {
      final pack = await makePack(heightOverflow: 12);

      final copy = await store.duplicatePlan(pack.id);

      expect(store.planRecordById(copy!.id)!.heightOverflow, 12);
    });

    test('duplicating copies the gear and the layout', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final original = store.planFor(pack.id)!.entries.single.placement!;

      final copy = await store.duplicatePlan(pack.id);

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
      expect(store.items.map((i) => i.name), ['daypack', 'mug']);
    });
  });

  group('loadouts', () {
    test('applying one adds all its gear', () async {
      final pack = await makePack();
      final mug = await makeMug();
      final stove = await store.addItem(name: 'stove', width: 12, height: 10);
      final loadout = await store.addLoadout(
        name: 'cook kit',
        itemIds: [mug.id, stove.id],
      );

      final unfitted = await store.applyLoadout(pack.id, loadout.id);

      expect(unfitted, isEmpty);
      expect(
        store.planFor(pack.id)!.entries.map((e) => e.item.name),
        ['mug', 'stove'],
      );
    });

    test('reports gear that found no room', () async {
      final tinyBag = await store.addItem(
        name: 'tiny',
        width: 10,
        height: 10,
        isContainer: true,
      );
      final pack = (await store.addPlan(containerItemId: tinyBag.id))!;
      final mug = await makeMug();
      final tent = await store.addItem(name: 'tent', width: 200, height: 200);
      final loadout = await store.addLoadout(
        name: 'kit',
        itemIds: [mug.id, tent.id],
      );

      final unfitted = await store.applyLoadout(pack.id, loadout.id);

      expect(unfitted.map((i) => i.name), ['tent']);
      // It is still added to the container, just not placed.
      expect(store.planFor(pack.id)!.entries, hasLength(2));
    });

    test('applying twice packs two of everything', () async {
      final pack = await makePack();
      final mug = await makeMug();
      final loadout = await store.addLoadout(name: 'kit', itemIds: [mug.id]);

      await store.applyLoadout(pack.id, loadout.id);
      await store.applyLoadout(pack.id, loadout.id);

      expect(store.planFor(pack.id)!.entries, hasLength(2));
    });

    test('a container can be saved as a loadout', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      await store.addGear(pack.id, mug.id);

      final loadout = await store.savePlanAsLoadout(
        pack.id,
        name: 'my kit',
      );

      // Two entries of the same item means "pack two of these".
      expect(loadout.itemIds, [mug.id, mug.id]);
    });

    test('deleting a loadout keeps the gear', () async {
      final mug = await makeMug();
      final loadout = await store.addLoadout(name: 'kit', itemIds: [mug.id]);

      await store.deleteLoadout(loadout.id);

      expect(store.loadouts, isEmpty);
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

      // Half the 2 cm tolerance sits against each wall.
      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.x, 1);
      expect(placement.y, 1);
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

    test(
      'a plan with height overflow allows gear above the real height',
      () async {
        final pack = await makePack(heightOverflow: 15);
        final mug = await makeMug();
        await store.addGear(pack.id, mug.id);
        final entryId = store.planFor(pack.id)!.entries.single.id;

        store.moveGear(pack.id, entryId, dy: 500);

        // The mug is 9 tall; the container is 40 tall with 15 of overflow.
        final placement = store.planFor(pack.id)!.entries.single.placement!;
        expect(placement.bottom, 55);
      },
    );

    test('height overflow still has a ceiling', () async {
      final pack = await makePack(heightOverflow: 15);
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dy: 5000);

      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.bottom, 55);
      store.moveGear(pack.id, entryId, dy: 1);
      expect(store.planFor(pack.id)!.entries.single.placement!.bottom, 55);
    });

    test('a plan with no height overflow behaves as before', () async {
      final pack = await makePack();
      final mug = await makeMug();
      await store.addGear(pack.id, mug.id);
      final entryId = store.planFor(pack.id)!.entries.single.id;

      store.moveGear(pack.id, entryId, dy: 500);

      expect(store.planFor(pack.id)!.entries.single.placement!.bottom, 40);
    });
  });

  group('adding and auto-packing gear with height overflow', () {
    test('addGear may use the overflow room', () async {
      final pack = await makePack(heightOverflow: 15);
      // 40 real height, plus 15 of overflow allows 55 - too tall to fit
      // without it.
      final tall = await store.addItem(name: 'tall', width: 10, height: 50);

      final added = await store.addGear(pack.id, tall.id);

      expect(added, isTrue);
      final placement = store.planFor(pack.id)!.entries.single.placement!;
      expect(placement.bottom, lessThanOrEqualTo(55));
    });

    test('addGear is still refused past the overflow limit', () async {
      final pack = await makePack(heightOverflow: 5);
      final tall = await store.addItem(name: 'tall', width: 10, height: 50);

      final added = await store.addGear(pack.id, tall.id);

      expect(added, isFalse);
      expect(store.planFor(pack.id)!.entries.single.placement, isNull);
    });

    test('auto-pack may use the overflow room too', () async {
      final pack = await makePack(heightOverflow: 15);
      final tall = await store.addItem(name: 'tall', width: 10, height: 50);
      await store.addGear(pack.id, tall.id);

      final result = await store.autoPack(pack.id);

      expect(result.everythingFits, isTrue);
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
      final pack = await makePack(depth: 20, tolerance: 1, heightOverflow: 6);
      final pot = await store.addItem(
        name: 'pot',
        width: 10,
        height: 10,
        depth: 8,
        tags: ['cook'],
        rotatable: false,
      );
      await store.addGear(pack.id, pot.id);
      await store.addLoadout(name: 'cook kit', itemIds: [pot.id]);

      final reloaded = await reload();

      final item = reloaded.itemById(pot.id)!;
      expect(item.name, 'pot');
      expect(item.depth, 8);
      expect(item.tags, ['cook']);
      expect(item.rotatable, isFalse);

      final record = reloaded.planRecordById(pack.id)!;
      expect(reloaded.planFor(pack.id)!.container.depth, 20);
      expect(record.tolerance, 1);
      expect(record.heightOverflow, 6);

      final plan = reloaded.planFor(pack.id)!;
      expect(plan.packed, hasLength(1));
      expect(reloaded.loadouts.single.itemIds, [pot.id]);
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

      expect(recovered.planRecords, isEmpty);
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

      // The old good and the old container both land in the library now.
      final mug = migrated.items.firstWhere((item) => item.name == 'mug');
      expect(mug.tags, isEmpty);
      expect(mug.isContainer, isFalse);

      final plan = migrated.planFor('container-1')!;
      expect(plan.tolerance, 0);
      expect(plan.container.name, 'daypack');
      expect(plan.container.isContainer, isTrue);
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
      // The old good, plus the old container lifted into the library.
      expect(json['items'], hasLength(2));
      expect(json['containers'], isNull);
      expect((json['plans'] as List).single['containerItemId'], isNotNull);

      // And it still loads cleanly the second time round.
      expect((await reload()).items, hasLength(2));
    });

    test('an empty version 1 file migrates to nothing', () async {
      await File(
        '${directory.path}/packplan.json',
      ).writeAsString(jsonEncode({'containers': <dynamic>[]}));

      final migrated = await reload();

      expect(migrated.items, isEmpty);
      expect(migrated.planRecords, isEmpty);
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

  test('loadouts saved under the old "recipes" key still load', () async {
    await File('${directory.path}/packplan.json').writeAsString(
      jsonEncode({
        'version': kSchemaVersion,
        'settings': <String, dynamic>{},
        'items': <dynamic>[],
        'recipes': [
          {'id': 'r1', 'name': 'cook kit', 'itemIds': <String>[]},
        ],
        'containers': <dynamic>[],
      }),
    );

    final reloaded = await reload();

    expect(reloaded.loadouts.single.name, 'cook kit');
  });

  group('migration from the separate-containers schema', () {
    test('an old container becomes library gear plus a plan', () async {
      // Exactly what version 2 wrote.
      await File('${directory.path}/packplan.json').writeAsString(
        jsonEncode({
          'version': 2,
          'settings': {'unitId': 'inches', 'defaultTolerance': 1.0},
          'items': [
            {
              'id': 'item-1',
              'name': 'mug',
              'width': 9.0,
              'height': 9.0,
              'colorValue': kGearPalette[1],
              'rotatable': true,
              'tags': ['cook'],
            },
          ],
          'recipes': <dynamic>[],
          'containers': [
            {
              'id': 'container-1',
              'name': 'daypack',
              'width': 30.0,
              'height': 40.0,
              'depth': 20.0,
              'colorValue': kGearPalette.first,
              'tolerance': 1.5,
              'entries': [
                {'id': 'entry-1', 'itemId': 'item-1'},
              ],
              'placements': {
                'entry-1': {
                  'entryId': 'entry-1',
                  'x': 2.0,
                  'y': 3.0,
                  'z': 4.0,
                  'width': 9.0,
                  'height': 9.0,
                  'depth': 1.0,
                },
              },
            },
          ],
          'customUnits': <dynamic>[],
        }),
      );

      final migrated = await reload();

      // The bag is now gear, and can be packed into something else in turn.
      final bag = migrated.items.firstWhere((item) => item.name == 'daypack');
      expect(bag.isContainer, isTrue);
      expect(bag.width, 30);
      expect(bag.depth, 20);
      expect(migrated.containerItems.map((i) => i.name), ['daypack']);

      // The plan keeps the container's id, name, tolerance and layout.
      final plan = migrated.planFor('container-1')!;
      expect(plan.name, 'daypack');
      expect(plan.tolerance, 1.5);
      expect(plan.container.id, bag.id);
      expect(plan.entries.single.item.name, 'mug');
      expect(plan.entries.single.placement!.x, 2);

      // Unrelated state rides through untouched.
      expect(migrated.unit.symbol, 'in');
      expect(migrated.settings.defaultTolerance, 1.0);
    });

    test('a version 1 file migrates all the way through', () async {
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

      expect(migrated.items.map((i) => i.name).toList()..sort(), [
        'daypack',
        'mug',
      ]);
      expect(migrated.planFor('container-1')!.container.name, 'daypack');
      expect(migrated.planFor('container-1')!.entries.single.item.name, 'mug');
    });

    test('migrating twice is a no-op', () async {
      await File('${directory.path}/packplan.json').writeAsString(
        jsonEncode({
          'version': 2,
          'items': <dynamic>[],
          'containers': [
            {
              'id': 'container-1',
              'name': 'daypack',
              'width': 30.0,
              'height': 40.0,
              'colorValue': kGearPalette.first,
              'tolerance': 0,
              'entries': <dynamic>[],
              'placements': <String, dynamic>{},
            },
          ],
        }),
      );

      final once = await reload();
      await once.flush();
      final twice = await reload();

      expect(twice.items, hasLength(1));
      expect(twice.planRecords, hasLength(1));
    });
  });

  group('turning gear by hand', () {
    /// The case from the screenshot: a 45 x 30 box lying flat in a 50-tall
    /// container that it would also fit standing up.
    Future<({String planId, String entryId})> chuckboxInCamp({
      double tolerance = 0,
      double containerDepth = 20,
    }) async {
      final bag = await store.addItem(
        name: 'Camp',
        width: 90,
        height: 50,
        depth: containerDepth,
        isContainer: true,
      );
      final plan = (await store.addPlan(
        containerItemId: bag.id,
        name: 'Camp',
        tolerance: tolerance,
      ))!;
      final box = await store.addItem(
        name: 'Chuckbox',
        width: 45,
        height: 30,
        depth: 20,
      );
      await store.addGear(plan.id, box.id);
      return (
        planId: plan.id,
        entryId: store.planFor(plan.id)!.entries.single.id,
      );
    }

    (double, double, double) dimsOf(String planId, String entryId) {
      final placement = store
          .planFor(planId)!
          .entries
          .firstWhere((e) => e.id == entryId)
          .placement!;
      return (placement.width, placement.height, placement.depth);
    }

    test('a turn moves to the next orientation', () async {
      final it = await chuckboxInCamp();
      expect(dimsOf(it.planId, it.entryId), (45.0, 30.0, 20.0));

      final outcome = await store.rotateGear(it.planId, it.entryId);

      expect(outcome, RotateOutcome.rotated);
      expect(dimsOf(it.planId, it.entryId), (30.0, 45.0, 20.0));
    });

    test(
      'a turn skips orientations the container cannot fit, cycling only '
      'through the rest',
      () async {
        // The screenshot's bag is only 20 cm deep - too shallow for any
        // orientation that stands the box up on its 30 or 45 cm side, so
        // repeated turns can only ever toggle between the two that keep its
        // 20 cm side as the depth.
        final it = await chuckboxInCamp();

        await store.rotateGear(it.planId, it.entryId);
        expect(dimsOf(it.planId, it.entryId), (30.0, 45.0, 20.0));

        await store.rotateGear(it.planId, it.entryId);
        expect(
          dimsOf(it.planId, it.entryId),
          (45.0, 30.0, 20.0),
          reason: 'back to the start - nothing deeper fits this bag',
        );
      },
    );

    test(
      'turning repeatedly visits every orientation and returns to the start',
      () async {
        final bag = await store.addItem(
          name: 'Trunk',
          width: 90,
          height: 90,
          depth: 90,
          isContainer: true,
        );
        final plan = (await store.addPlan(
          containerItemId: bag.id,
          name: 'Trunk',
        ))!;
        final box = await store.addItem(
          name: 'Chuckbox',
          width: 45,
          height: 30,
          depth: 20,
        );
        await store.addGear(plan.id, box.id);
        final entryId = store.planFor(plan.id)!.entries.single.id;

        final start = dimsOf(plan.id, entryId);
        final visited = {start};
        for (var i = 0; i < 5; i++) {
          await store.rotateGear(plan.id, entryId);
          visited.add(dimsOf(plan.id, entryId));
        }
        expect(
          visited,
          hasLength(6),
          reason: 'every permutation of 45/30/20 is distinct',
        );

        await store.rotateGear(plan.id, entryId);
        expect(
          dimsOf(plan.id, entryId),
          start,
          reason: 'the sixth turn closes the cycle',
        );
      },
    );

    test('a cube has nowhere else to turn', () async {
      final bag = await store.addItem(
        name: 'Trunk',
        width: 90,
        height: 90,
        depth: 90,
        isContainer: true,
      );
      final plan = (await store.addPlan(containerItemId: bag.id))!;
      final die = await store.addItem(
        name: 'die',
        width: 10,
        height: 10,
        depth: 10,
      );
      await store.addGear(plan.id, die.id);
      final entryId = store.planFor(plan.id)!.entries.single.id;

      expect(
        await store.rotateGear(plan.id, entryId),
        RotateOutcome.wontFit,
      );
    });

    test('a turn that only pokes through an open top is allowed', () async {
      final bag = await store.addItem(
        name: 'wagon',
        width: 90,
        height: 20,
        isContainer: true,
      );
      final plan = (await store.addPlan(
        containerItemId: bag.id,
        heightOverflow: 65,
      ))!;
      final plank = await store.addItem(name: 'plank', width: 80, height: 10);
      await store.addGear(plan.id, plank.id);
      final entryId = store.planFor(plan.id)!.entries.single.id;

      // Standing it up needs 80 of height - only 20 real, but the 65 of
      // overflow this open-top wagon allows covers the rest.
      final outcome = await store.rotateGear(plan.id, entryId);

      expect(outcome, RotateOutcome.rotated);
      final after = store.planFor(plan.id)!.entries.single.placement!;
      expect(after.width, 10);
      expect(after.height, 80);
      expect(after.bottom, lessThanOrEqualTo(85));
    });

    test('a turn is still refused past the overflow limit', () async {
      final bag = await store.addItem(
        name: 'wagon',
        width: 90,
        height: 20,
        isContainer: true,
      );
      final plan = (await store.addPlan(
        containerItemId: bag.id,
        heightOverflow: 50,
      ))!;
      final plank = await store.addItem(name: 'plank', width: 80, height: 10);
      await store.addGear(plan.id, plank.id);
      final entryId = store.planFor(plan.id)!.entries.single.id;

      // Standing it up needs 80 of height - only 70 available even counting
      // the overflow.
      final outcome = await store.rotateGear(plan.id, entryId);

      expect(outcome, RotateOutcome.wontFit);
    });

    test('depthless gear only ever turns width against height', () async {
      final bag = await store.addItem(
        name: 'Camp',
        width: 90,
        height: 50,
        depth: 20,
        isContainer: true,
      );
      final plan = (await store.addPlan(containerItemId: bag.id))!;
      final map = await store.addItem(name: 'map', width: 20, height: 14);
      await store.addGear(plan.id, map.id);
      final entryId = store.planFor(plan.id)!.entries.single.id;

      // Real measurements, so this is fine.
      expect(
        await store.rotateGear(plan.id, entryId),
        RotateOutcome.rotated,
      );
      final after = store.planFor(plan.id)!.entries.single.placement!;
      expect(after.width, 14);
      expect(after.height, 20);
      expect(
        after.depth,
        1,
        reason: 'never stood up on the depth the app invented for it',
      );
    });

    test('turning ignores the packer-only "can be turned" setting', () async {
      final bag = await store.addItem(
        name: 'Camp',
        width: 90,
        height: 50,
        isContainer: true,
      );
      final plan = (await store.addPlan(containerItemId: bag.id))!;
      final stove = await store.addItem(
        name: 'stove',
        width: 20,
        height: 10,
        rotatable: false,
      );
      await store.addGear(plan.id, stove.id);
      final entryId = store.planFor(plan.id)!.entries.single.id;

      // That switch governs auto-pack; this is the user saying otherwise about
      // one placement.
      expect(
        await store.rotateGear(plan.id, entryId),
        RotateOutcome.rotated,
      );
      expect(store.planFor(plan.id)!.entries.single.placement!.height, 20);
    });

    test('a turn near an edge is pulled back inside', () async {
      final bag = await store.addItem(
        name: 'Camp',
        width: 90,
        height: 50,
        isContainer: true,
      );
      final plan = (await store.addPlan(containerItemId: bag.id))!;
      final box = await store.addItem(name: 'box', width: 40, height: 10);
      await store.addGear(plan.id, box.id);
      final entryId = store.planFor(plan.id)!.entries.single.id;

      // Push it to the top, where standing it up would poke out of the lid.
      store.moveGear(plan.id, entryId, dy: 100);
      expect(store.planFor(plan.id)!.entries.single.placement!.y, 40);

      await store.rotateGear(plan.id, entryId);

      final after = store.planFor(plan.id)!.entries.single.placement!;
      expect(after.height, 40);
      expect(after.bottom, lessThanOrEqualTo(50));
    });

    test('a turn respects the tolerance margin', () async {
      // A 2 cm gap on every wall leaves only 16 cm of depth in the screenshot's
      // bag, which the box cannot fit in at all, so give it a deeper one.
      final it = await chuckboxInCamp(tolerance: 2, containerDepth: 30);

      await store.rotateGear(it.planId, it.entryId);

      final after = store.planFor(it.planId)!.entries.single.placement!;
      expect(after.x, greaterThanOrEqualTo(1));
      expect(after.y, greaterThanOrEqualTo(1));
      expect(after.right, lessThanOrEqualTo(89));
      expect(after.bottom, lessThanOrEqualTo(49));
      expect(after.back, lessThanOrEqualTo(29));
    });

    test('unplaced gear cannot be turned', () async {
      final it = await chuckboxInCamp();
      await store.unplaceEntry(it.planId, it.entryId);

      expect(
        await store.rotateGear(it.planId, it.entryId),
        RotateOutcome.notFound,
      );
    });

    test('a turn survives a reload', () async {
      final it = await chuckboxInCamp();
      await store.rotateGear(it.planId, it.entryId);

      final reloaded = await reload();

      final after = reloaded.planFor(it.planId)!.entries.single.placement!;
      expect(after.width, 30);
      expect(after.height, 45);
    });

    test('auto-pack discards a hand turn, like it discards a drag', () async {
      final it = await chuckboxInCamp();
      await store.rotateGear(it.planId, it.entryId);

      await store.autoPack(it.planId);

      final after = store.planFor(it.planId)!.entries.single.placement!;
      expect(after.width, 45);
      expect(after.height, 30);
    });
  });

  group('view visibility', () {
    Future<PlanRecord> trolley() async {
      final bag = await store.addItem(
        name: 'Trolley bag',
        width: 60,
        height: 300,
        depth: 40,
        isContainer: true,
      );
      return (await store.addPlan(
        containerItemId: bag.id,
        name: 'Trolley',
      ))!;
    }

    test('front and 3D start hidden - top and side are the default pair', () async {
      final plan = await trolley();

      expect(store.planRecordById(plan.id)!.hiddenViews, {'front', '3d'});
    });

    test('hiding is remembered per view', () async {
      final plan = await trolley();

      await store.toggleViewVisibility(plan.id, 'side');

      expect(store.planRecordById(plan.id)!.hiddenViews, {
        'front',
        '3d',
        'side',
      });
      expect(store.planFor(plan.id)!.hiddenViews, contains('side'));
    });

    test('toggling a hidden view shows it again', () async {
      final plan = await trolley();

      await store.toggleViewVisibility(plan.id, 'front');

      expect(store.planRecordById(plan.id)!.hiddenViews, {'3d'});
    });

    test('the 3D preview toggles the same way as an axis-based view', () async {
      final plan = await trolley();

      await store.toggleViewVisibility(plan.id, '3d');
      expect(store.planRecordById(plan.id)!.hiddenViews, {'front'});

      await store.toggleViewVisibility(plan.id, '3d');
      expect(store.planRecordById(plan.id)!.hiddenViews, {'front', '3d'});
    });

    test('hiding moves nothing', () async {
      final plan = await trolley();
      final box = await store.addItem(
        name: 'box',
        width: 20,
        height: 20,
        depth: 20,
      );
      await store.addGear(plan.id, box.id);
      final before = store.planFor(plan.id)!.entries.single.placement!;

      await store.toggleViewVisibility(plan.id, 'side');

      // Purely how it is drawn.
      final after = store.planFor(plan.id)!.entries.single.placement!;
      expect(after.x, before.x);
      expect(after.y, before.y);
      expect(after.z, before.z);
    });

    test('hiding survives a reload', () async {
      final plan = await trolley();
      await store.toggleViewVisibility(plan.id, 'side');

      final reloaded = await reload();

      expect(reloaded.planRecordById(plan.id)!.hiddenViews, {'front', '3d', 'side'});
    });

    test('a duplicated plan keeps which views are hidden', () async {
      final plan = await trolley();
      await store.toggleViewVisibility(plan.id, 'side');

      final copy = await store.duplicatePlan(plan.id);

      expect(store.planRecordById(copy!.id)!.hiddenViews, {'front', '3d', 'side'});
    });
  });
}
