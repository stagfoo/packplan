import 'package:flutter/material.dart';

import 'container_list_screen.dart';
import 'store.dart';

void main() {
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
      home: ContainerListScreen(store: store),
    );
  }
}
