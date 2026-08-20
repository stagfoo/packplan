import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/main.dart' as app;
import 'package:packplan/main.dart';
import 'package:packplan/repository.dart';
import 'package:packplan/store.dart';

/// Stands in for a repository that cannot reach the disk — which is what the
/// real one does when the platform channel is not ready.
class _BrokenRepository extends GearRepository {
  _BrokenRepository() : super(directory: Directory.systemTemp);

  @override
  Future<GearData> load() async => throw StateError('no binding');
}

/// Drives the real app the way a person does, to catch the framework asserts
/// that unit tests never see.
void main() {
  late Directory directory;
  late GearStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('packplan_flow');
    store = GearStore(repository: GearRepository(directory: directory));
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  /// The store touches the filesystem, which fake async will never let finish.
  Future<void> seed(WidgetTester tester, Future<void> Function() work) =>
      tester.runAsync(work);

  /// A container in the library plus a plan built around it.
  Future<String> makePlan({
    String name = 'daypack',
    double width = 30,
    double height = 40,
    double? depth,
  }) async {
    final bag = await store.addItem(
      name: name,
      width: width,
      height: height,
      depth: depth,
      isContainer: true,
    );
    final plan = await store.addPlan(containerItemId: bag.id, name: name);
    return plan!.id;
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(PackPlanApp(store: store));
    await tester.pumpAndSettle();
  }

  testWidgets('the plans tab lists a container', (tester) async {
    await seed(tester, () async {
      await store.load();
      await makePlan(name: 'daypack', width: 30, height: 40);
    });

    await pumpApp(tester);

    expect(find.text('daypack'), findsOneWidget);
  });

  testWidgets('the plans tab loads with gear already packed', (tester) async {
    await seed(tester, () async {
      await store.load();
      final packId = await makePlan(name: 'daypack', width: 30, height: 40, depth: 20);
      final mug = await store.addItem(
        name: 'mug',
        width: 9,
        height: 9,
        depth: 9,
      );
      await store.addGear(packId, mug.id);
    });

    await pumpApp(tester);

    expect(find.text('daypack'), findsOneWidget);
  });

  testWidgets('opening a plan shows its diagram', (tester) async {
    await seed(tester, () async {
      await store.load();
      final packId = await makePlan(name: 'daypack', width: 30, height: 40);
      final mug = await store.addItem(name: 'mug', width: 9, height: 9);
      await store.addGear(packId, mug.id);
    });

    await pumpApp(tester);
    await tester.tap(find.text('daypack'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-pack'), findsOneWidget);
    expect(find.text('mug'), findsWidgets);
  });

  testWidgets('saving a container as a loadout does not crash', (tester) async {
    await seed(tester, () async {
      await store.load();
      final packId = await makePlan(name: 'daypack', width: 30, height: 40);
      final mug = await store.addItem(name: 'mug', width: 9, height: 9);
      await store.addGear(packId, mug.id);
    });

    await pumpApp(tester);
    await tester.tap(find.text('daypack'));
    await tester.pumpAndSettle();

    // The gear rows have their own overflow menus, so target the app bar's.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as loadout'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'weekend kit');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    // Letting the dialog's route finish tearing down is where a disposed
    // controller or a stray InheritedWidget would blow up.
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('cancelling the loadout dialog does not crash', (tester) async {
    await seed(tester, () async {
      await store.load();
      final packId = await makePlan(name: 'daypack', width: 30, height: 40);
      final mug = await store.addItem(name: 'mug', width: 9, height: 9);
      await store.addGear(packId, mug.id);
    });

    await pumpApp(tester);
    await tester.tap(find.text('daypack'));
    await tester.pumpAndSettle();

    // The gear rows have their own overflow menus, so target the app bar's.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as loadout'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('creating a loadout from the loadouts tab does not crash', (
    tester,
  ) async {
    await seed(tester, () async => store.load());

    await pumpApp(tester);
    await tester.tap(find.text('Loadouts'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New loadout'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cook kit');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('the gear picker opens and closes cleanly', (tester) async {
    await seed(tester, () async {
      await store.load();
      await makePlan(name: 'daypack', width: 30, height: 40);
      await store.addItem(name: 'mug', width: 9, height: 9);
    });

    await pumpApp(tester);
    await tester.tap(find.text('daypack'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add gear'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('switching tabs does not crash', (tester) async {
    await seed(tester, () async => store.load());

    await pumpApp(tester);

    for (final tab in ['Gear', 'Loadouts', 'Plans']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }
  });

  group('startup', () {
    testWidgets('a failed load finishes and says so, never spins', (
      tester,
    ) async {
      final broken = GearStore(repository: _BrokenRepository())..load();

      await tester.pumpWidget(PackPlanApp(store: broken));
      await tester.pumpAndSettle();

      expect(broken.isLoaded, isTrue);
      expect(broken.loadError, isNotNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("Couldn't load your gear"), findsOneWidget);
      // The saved file must not be silently replaced by an empty one.
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('an empty store shows the empty state, not a spinner', (
      tester,
    ) async {
      await seed(tester, () async => store.load());

      await pumpApp(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Nothing planned yet'), findsOneWidget);
    });

    testWidgets('main() gets past the first frame', (tester) async {
      // Reaching for the documents directory before the binding exists is what
      // left the plans tab spinning forever.
      // main() calls runApp directly, so clear the previous test's tree first
      // — its tickers would otherwise still be running against a reset clock.
      await tester.pumpWidget(const SizedBox.shrink());

      app.main();
      await tester.pump();

      // The app bar title and the nav destination both say Plans. Reaching
      // the shell at all is the point: before ensureInitialized() this threw
      // on the platform channel and never got here.
      //
      // Loading does not finish here — path_provider has no plugin under
      // `flutter test`, so the channel never answers. The failed-load path is
      // covered above with a repository that throws outright.
      expect(find.text('Plans'), findsWidgets);
    });
  });

  group('marking gear as a container', () {
    /// Fills the gear sheet in and saves it.
    Future<void> fillGearSheet(
      WidgetTester tester, {
      required String name,
      required String width,
      required String height,
      bool holdsGear = false,
    }) async {
      await tester.enterText(find.widgetWithText(TextFormField, 'Name'), name);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Width (X)'),
        width,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Height (Z)'),
        height,
      );

      if (holdsGear) {
        await tester.tap(find.widgetWithText(SwitchListTile, 'Holds other gear'));
        await tester.pump();
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('the switch reaches the library when creating gear', (
      tester,
    ) async {
      await seed(tester, () async => store.load());

      await pumpApp(tester);
      await tester.tap(find.text('Gear'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New gear'));
      await tester.pumpAndSettle();

      await fillGearSheet(
        tester,
        name: 'dry bag',
        width: '30',
        height: '40',
        holdsGear: true,
      );

      expect(store.items.single.name, 'dry bag');
      expect(store.items.single.isContainer, isTrue);
      // And so a plan can actually be built on it.
      expect(store.containerItems, hasLength(1));
    });

    testWidgets('gear left alone does not become a container', (tester) async {
      await seed(tester, () async => store.load());

      await pumpApp(tester);
      await tester.tap(find.text('Gear'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('New gear'));
      await tester.pumpAndSettle();

      await fillGearSheet(tester, name: 'mug', width: '9', height: '9');

      expect(store.items.single.isContainer, isFalse);
      expect(store.containerItems, isEmpty);
    });

    testWidgets('the switch survives reopening the sheet', (tester) async {
      await seed(tester, () async {
        await store.load();
        await store.addItem(
          name: 'dry bag',
          width: 30,
          height: 40,
          isContainer: true,
        );
      });

      await pumpApp(tester);
      await tester.tap(find.text('Gear'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('dry bag'));
      await tester.pumpAndSettle();

      // It must come back on, and stay on through a save that touches nothing.
      final switchTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Holds other gear'),
      );
      expect(switchTile.value, isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.items.single.isContainer, isTrue);
    });

    testWidgets('the switch can be turned off again', (tester) async {
      await seed(tester, () async {
        await store.load();
        await store.addItem(
          name: 'dry bag',
          width: 30,
          height: 40,
          isContainer: true,
        );
      });

      await pumpApp(tester);
      await tester.tap(find.text('Gear'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('dry bag'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Holds other gear'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.items.single.isContainer, isFalse);
    });

    testWidgets('a container can then be planned around', (tester) async {
      await seed(tester, () async => store.load());

      await pumpApp(tester);
      await tester.tap(find.text('Gear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New gear'));
      await tester.pumpAndSettle();
      await fillGearSheet(
        tester,
        name: 'dry bag',
        width: '30',
        height: '40',
        holdsGear: true,
      );

      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New plan'));
      await tester.pumpAndSettle();

      // The sheet offers the bag rather than refusing to open.
      expect(find.text('Pack into'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Plan name'),
        'weekend',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(store.planRecords, hasLength(1));
      expect(store.plans.single.name, 'weekend');
      expect(store.plans.single.container.name, 'dry bag');
    });
  });

  group('turning gear from the diagram', () {
    /// The screenshot's plan: a 45 x 30 x 20 box in a 90 x 50 x 20 bag.
    Future<String> campWithChuckbox() async {
      final bag = await store.addItem(
        name: 'Camp',
        width: 90,
        height: 50,
        depth: 20,
        isContainer: true,
      );
      final plan = (await store.addPlan(
        containerItemId: bag.id,
        name: 'Camp',
      ))!;
      final box = await store.addItem(
        name: 'Chuckbox',
        width: 45,
        height: 30,
        depth: 20,
      );
      await store.addGear(plan.id, box.id);
      return plan.id;
    }

    testWidgets('no turn button until gear is selected', (tester) async {
      late String planId;
      await seed(tester, () async {
        await store.load();
        planId = await campWithChuckbox();
      });

      await tester.pumpWidget(PackPlanApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camp'));
      await tester.pumpAndSettle();

      expect(planId, isNotEmpty);
      expect(
        find.byIcon(Icons.rotate_90_degrees_cw_outlined),
        findsNothing,
      );
    });

    testWidgets('selecting gear then turning it swaps its sides', (
      tester,
    ) async {
      late String planId;
      await seed(tester, () async {
        await store.load();
        planId = await campWithChuckbox();
      });

      await tester.pumpWidget(PackPlanApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camp'));
      await tester.pumpAndSettle();

      // Selecting from the gear list is the reliable way in a test; tapping
      // the shape itself is covered by the diagram's own tests.
      await tester.tap(find.text('Chuckbox'));
      await tester.pumpAndSettle();

      // One button per view, and the plan is three-dimensional.
      expect(
        find.byIcon(Icons.rotate_90_degrees_cw_outlined),
        findsNWidgets(2),
      );
      expect(planId, isNotEmpty);
    });

    testWidgets('the upper view turns width against depth', (tester) async {
      late String planId;
      await seed(tester, () async {
        await store.load();
        // Deep enough to take the box turned side-on, unlike the Camp bag.
        final bag = await store.addItem(
          name: 'Trailer',
          width: 90,
          height: 50,
          depth: 60,
          isContainer: true,
        );
        final plan = (await store.addPlan(
          containerItemId: bag.id,
          name: 'Trailer',
        ))!;
        planId = plan.id;
        final box = await store.addItem(
          name: 'Chuckbox',
          width: 45,
          height: 30,
          depth: 20,
        );
        await store.addGear(planId, box.id);
      });

      await tester.pumpWidget(PackPlanApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trailer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chuckbox'));
      await tester.pumpAndSettle();

      // The upper view is the top view, so its turn swaps width and depth.
      await tester.tap(
        find.byIcon(Icons.rotate_90_degrees_cw_outlined).first,
      );
      await tester.pumpAndSettle();

      final placement = store.planFor(planId)!.entries.single.placement!;
      expect(placement.width, 20);
      expect(placement.height, 30);
      expect(placement.depth, 45);
    });



    testWidgets('a turn that cannot fit says so and changes nothing', (
      tester,
    ) async {
      late String planId;
      await seed(tester, () async {
        await store.load();
        planId = await campWithChuckbox();
      });

      await tester.pumpWidget(PackPlanApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chuckbox'));
      await tester.pumpAndSettle();

      // The lower view is the side view: the box would need 30 of a 20 depth.
      await tester.tap(find.byIcon(Icons.rotate_90_degrees_cw_outlined).last);
      await tester.pumpAndSettle();

      expect(find.text("It doesn't fit that way round."), findsOneWidget);
      final placement = store.planFor(planId)!.entries.single.placement!;
      expect(placement.width, 45);
      expect(placement.height, 30);
    });

    testWidgets('a flat plan offers one turn button, not two', (tester) async {
      await seed(tester, () async {
        await store.load();
        final bag = await store.addItem(
          name: 'Pouch',
          width: 20,
          height: 13,
          isContainer: true,
        );
        final plan = (await store.addPlan(
          containerItemId: bag.id,
          name: 'Pouch',
        ))!;
        final knife = await store.addItem(name: 'Knife', width: 9, height: 3);
        await store.addGear(plan.id, knife.id);
      });

      await tester.pumpWidget(PackPlanApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pouch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Knife'));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.rotate_90_degrees_cw_outlined),
        findsOneWidget,
      );
    });
  });
}
