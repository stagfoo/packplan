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
}
