import 'package:flutter/material.dart';

import 'plan_list_screen.dart';
import 'diagram.dart';
import 'gear_library_screen.dart';
import 'loadouts_screen.dart';
import 'store.dart';

void main() {
  // load() reaches for the documents directory over a platform channel, which
  // does not exist until the binding does. Without this it throws before the
  // first frame and the app sits on a spinner forever.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PackPlanApp(store: GearStore()..load()));
}

class PackPlanApp extends StatelessWidget {
  const PackPlanApp({super.key, required this.store});

  final GearStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PackPlan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
      ),
      // The chosen unit is needed by almost every screen, so it is published
      // once here rather than threaded through every constructor.
      builder: (context, child) => ListenableBuilder(
        listenable: store,
        builder: (context, _) =>
            UnitScope(unit: store.unit, child: child ?? const SizedBox()),
      ),
      home: HomeShell(store: store),
    );
  }
}

/// Plans, gear and loadouts, with settings reachable from the plans tab.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final GearStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          PlanListScreen(store: widget.store),
          GearLibraryScreen(store: widget.store),
          LoadoutsScreen(store: widget.store),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.backpack_outlined),
            selectedIcon: Icon(Icons.backpack),
            label: 'Plans',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: 'Gear',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Loadouts',
          ),
        ],
      ),
    );
  }
}
