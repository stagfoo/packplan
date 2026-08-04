import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/models.dart';
import 'package:packplan/repository.dart';
import 'package:packplan/store.dart';

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

  Future<GearContainer> makePack({double? depth}) => store.addContainer(
    name: 'daypack',
    width: 30,
    height: 40,
    depth: depth,
  );

  group('containers', () {
    test('starts empty', () {
      expect(store.containers, isEmpty);
      expect(store.isLoaded, isTrue);
    });

    test('adding a container makes it retrievable', () async {
      final container = await makePack();

      expect(store.containers, hasLength(1));
      expect(store.containerById(container.id)!.name, 'daypack');
    });

    test('gives new containers different colours', () async {
      final first = await makePack();
      final second = await makePack();

      expect(first.colorValue, isNot(second.colorValue));
    });

    test('deleting removes it', () async {
      final container = await makePack();
      await store.deleteContainer(container.id);

      expect(store.containers, isEmpty);
      expect(store.containerById(container.id), isNull);
    });

    test('resizing re-packs so nothing is left hanging outside', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mat', width: 28, height: 30);

      await store.updateContainer(
        container.id,
        name: 'daypack',
        width: 20,
        height: 20,
      );

      final updated = store.containerById(container.id)!;
      // The mat no longer fits, so it must be reported rather than clipped.
      expect(updated.unpackedGoods.map((g) => g.name), ['mat']);
    });

    test('renaming alone leaves placements untouched', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.single.id;
      final before = store.containerById(container.id)!.placements[goodId]!;

      await store.updateContainer(
        container.id,
        name: 'summit pack',
        width: 30,
        height: 40,
      );

      final after = store.containerById(container.id)!;
      expect(after.name, 'summit pack');
      expect(after.placements[goodId]!.x, before.x);
      expect(after.placements[goodId]!.y, before.y);
    });

    test('dropping the depth turns a 3D plan flat', () async {
      final container = await makePack(depth: 20);
      await store.addGood(
        container.id,
        name: 'pot',
        width: 10,
        height: 10,
        depth: 10,
      );

      await store.updateContainer(
        container.id,
        name: 'daypack',
        width: 30,
        height: 40,
      );

      final updated = store.containerById(container.id)!;
      expect(updated.depth, isNull);
      expect(updated.isThreeDimensional, isFalse);
    });
  });

  group('goods', () {
    test('a new good is placed without disturbing the others', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'stove', width: 12, height: 10);
      final stoveBefore =
          store.containerById(container.id)!.placements.values.first;

      await store.addGood(container.id, name: 'mug', width: 9, height: 9);

      final updated = store.containerById(container.id)!;
      final stoveAfter = updated.placements[updated.goods.first.id]!;
      expect(stoveAfter.x, stoveBefore.x);
      expect(stoveAfter.y, stoveBefore.y);
      expect(updated.placements, hasLength(2));
    });

    test('a good too big to fit is kept but not placed', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'tent', width: 200, height: 200);

      final updated = store.containerById(container.id)!;
      expect(updated.goods, hasLength(1));
      expect(updated.placements, isEmpty);
      expect(updated.unpackedGoods.map((g) => g.name), ['tent']);
    });

    test('resizing a good finds it a new spot', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      await store.updateGood(
        container.id,
        goodId,
        name: 'mug',
        width: 20,
        height: 20,
        rotatable: true,
      );

      final placement = store.containerById(container.id)!.placements[goodId]!;
      expect(placement.width, 20);
      expect(placement.height, 20);
    });

    test('deleting a good clears its placement too', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      await store.deleteGood(container.id, goodId);

      final updated = store.containerById(container.id)!;
      expect(updated.goods, isEmpty);
      expect(updated.placements, isEmpty);
    });

    test('a good can be taken out and put back', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      await store.unplaceGood(container.id, goodId);
      expect(store.containerById(container.id)!.placements, isEmpty);

      expect(await store.placeGood(container.id, goodId), isTrue);
      expect(store.containerById(container.id)!.placements, hasLength(1));
    });

    test('putting back reports failure when there is no room', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'slab', width: 30, height: 40);
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);

      final mugId = store
          .containerById(container.id)!
          .goods
          .firstWhere((g) => g.name == 'mug')
          .id;

      expect(await store.placeGood(container.id, mugId), isFalse);
    });
  });

  group('moving', () {
    test('a drag shifts the good and snaps to the grid', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      store.moveGood(container.id, goodId, dx: 5.3, dy: 2.2);

      final placement = store.containerById(container.id)!.placements[goodId]!;
      expect(placement.x, 5.5);
      expect(placement.y, 2.0);
    });

    test('a good cannot be dragged out of the container', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      store.moveGood(container.id, goodId, dx: 500, dy: 500);

      final placement = store.containerById(container.id)!.placements[goodId]!;
      expect(placement.right, lessThanOrEqualTo(30));
      expect(placement.bottom, lessThanOrEqualTo(40));
    });

    test('a good cannot be dragged past the near edge either', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      store.moveGood(container.id, goodId, dx: -500, dy: -500);

      final placement = store.containerById(container.id)!.placements[goodId]!;
      expect(placement.x, 0);
      expect(placement.y, 0);
    });

    test('depth is fixed at zero in a flat plan', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      store.moveGood(container.id, goodId, dz: 10);

      expect(store.containerById(container.id)!.placements[goodId]!.z, 0);
    });

    test('depth can be dragged in a 3D plan', () async {
      final container = await makePack(depth: 20);
      await store.addGood(
        container.id,
        name: 'pot',
        width: 10,
        height: 10,
        depth: 5,
      );
      final goodId = store.containerById(container.id)!.goods.first.id;

      store.moveGood(container.id, goodId, dz: 8);

      expect(store.containerById(container.id)!.placements[goodId]!.z, 8);
    });

    test('overlaps from a drag are allowed, not blocked', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'a', width: 10, height: 10);
      await store.addGood(container.id, name: 'b', width: 10, height: 10);
      final updated = store.containerById(container.id)!;
      final bId = updated.goods.firstWhere((g) => g.name == 'b').id;

      // Drag b straight onto a.
      final b = updated.placements[bId]!;
      store.moveGood(container.id, bId, dx: -b.x, dy: -b.y);

      final moved = store.containerById(container.id)!.placements[bId]!;
      expect(moved.x, 0);
      expect(moved.y, 0);
    });
  });

  group('auto-pack', () {
    test('reports what did not fit', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      await store.addGood(container.id, name: 'tent', width: 200, height: 200);

      final result = await store.autoPack(container.id);

      expect(result.everythingFits, isFalse);
      expect(result.unfitted.map((g) => g.name), ['tent']);
    });

    test('discards manual positions', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      store.moveGood(container.id, goodId, dx: 15, dy: 15);
      await store.autoPack(container.id);

      final placement = store.containerById(container.id)!.placements[goodId]!;
      expect(placement.x, 0);
      expect(placement.y, 0);
    });
  });

  group('persistence', () {
    test('survives a reload', () async {
      final container = await makePack(depth: 20);
      await store.addGood(
        container.id,
        name: 'pot',
        width: 10,
        height: 10,
        depth: 8,
      );

      final reloaded = GearStore(
        repository: GearRepository(directory: directory),
      );
      await reloaded.load();

      final loaded = reloaded.containerById(container.id)!;
      expect(loaded.name, 'daypack');
      expect(loaded.depth, 20);
      expect(loaded.goods.single.name, 'pot');
      expect(loaded.goods.single.depth, 8);
      expect(loaded.placements, hasLength(1));
    });

    test('drag positions are written out on flush', () async {
      final container = await makePack();
      await store.addGood(container.id, name: 'mug', width: 9, height: 9);
      final goodId = store.containerById(container.id)!.goods.first.id;

      store.moveGood(container.id, goodId, dx: 10, dy: 10);
      await store.flush();

      final reloaded = GearStore(
        repository: GearRepository(directory: directory),
      );
      await reloaded.load();

      expect(reloaded.containerById(container.id)!.placements[goodId]!.x, 10);
    });

    test('a corrupt file does not stop the app starting', () async {
      await File('${directory.path}/packplan.json').writeAsString('not json');

      final recovered = GearStore(
        repository: GearRepository(directory: directory),
      );
      await recovered.load();

      expect(recovered.containers, isEmpty);
      expect(recovered.isLoaded, isTrue);
    });

    test('rotatable survives a round trip', () async {
      final container = await makePack();
      await store.addGood(
        container.id,
        name: 'pole',
        width: 5,
        height: 20,
        rotatable: false,
      );

      final reloaded = GearStore(
        repository: GearRepository(directory: directory),
      );
      await reloaded.load();

      expect(reloaded.containerById(container.id)!.goods.single.rotatable,
          isFalse);
    });
  });
}
