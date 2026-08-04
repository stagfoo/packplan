import 'dart:ui' show Color;

import 'units.dart';

/// Every length in this file is centimetres. See [MeasurementUnit] — units are
/// a display concern, never a storage one.

/// Where a piece of gear sits inside its container.
class Placement {
  const Placement({
    required this.entryId,
    required this.x,
    required this.y,
    required this.z,
    required this.width,
    required this.height,
    required this.depth,
  });

  /// The container entry this positions — not the library item, so two of the
  /// same thing can sit in different places.
  final String entryId;

  final double x;
  final double y;
  final double z;

  /// The gear's dimensions *as placed*. The packer may turn gear, so these can
  /// be a permutation of the item's own dimensions.
  final double width;
  final double height;
  final double depth;

  double get right => x + width;
  double get bottom => y + height;
  double get back => z + depth;

  Placement copyWith({double? x, double? y, double? z}) => Placement(
    entryId: entryId,
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    width: width,
    height: height,
    depth: depth,
  );

  /// True when this placement comes within [clearance] of [other] on every
  /// axis. With a clearance of zero, touching faces do not count.
  bool overlaps(Placement other, {double clearance = 0}) {
    return x < other.right + clearance &&
        other.x < right + clearance &&
        y < other.bottom + clearance &&
        other.y < bottom + clearance &&
        z < other.back + clearance &&
        other.z < back + clearance;
  }

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'x': x,
    'y': y,
    'z': z,
    'width': width,
    'height': height,
    'depth': depth,
  };

  factory Placement.fromJson(Map<String, dynamic> json) => Placement(
    entryId: json['entryId'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    depth: (json['depth'] as num).toDouble(),
  );
}

/// A piece of gear in your library, defined once and used in any number of
/// containers.
class GearItem {
  const GearItem({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.depth,
    required this.colorValue,
    this.rotatable = true,
    this.tags = const [],
  });

  final String id;
  final String name;
  final double width;
  final double height;

  /// Optional. Gear without a depth is treated as flat.
  final double? depth;

  final int colorValue;

  /// Whether the packer may turn this to make it fit. Some gear only packs one
  /// way up.
  final bool rotatable;

  /// Lowercase, deduplicated. See [normaliseTags].
  final List<String> tags;

  Color get color => Color(colorValue);

  bool get hasDepth => depth != null;

  double get area => width * height;

  double get volume => width * height * (depth ?? 0);

  /// The length along one axis, or null for depth on flat gear.
  double? dimension(GearAxis axis) => switch (axis) {
    GearAxis.width => width,
    GearAxis.height => height,
    GearAxis.depth => depth,
  };

  /// The axis a derived unit should default to — the longest one, since that
  /// is what you would naturally lay against something to measure it.
  GearAxis get longestAxis {
    var best = GearAxis.width;
    var bestLength = width;
    if (height > bestLength) {
      best = GearAxis.height;
      bestLength = height;
    }
    if ((depth ?? 0) > bestLength) best = GearAxis.depth;
    return best;
  }

  GearItem copyWith({
    String? name,
    double? width,
    double? height,
    double? depth,
    bool clearDepth = false,
    int? colorValue,
    bool? rotatable,
    List<String>? tags,
  }) => GearItem(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    depth: clearDepth ? null : (depth ?? this.depth),
    colorValue: colorValue ?? this.colorValue,
    rotatable: rotatable ?? this.rotatable,
    tags: tags ?? this.tags,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    if (depth != null) 'depth': depth,
    'colorValue': colorValue,
    'rotatable': rotatable,
    'tags': tags,
  };

  factory GearItem.fromJson(Map<String, dynamic> json) => GearItem(
    id: json['id'] as String,
    name: json['name'] as String,
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    depth: (json['depth'] as num?)?.toDouble(),
    colorValue: json['colorValue'] as int,
    rotatable: json['rotatable'] as bool? ?? true,
    tags: normaliseTags(
      (json['tags'] as List<dynamic>? ?? []).map((tag) => tag as String),
    ),
  );
}

/// Tags are matched by equality all over the app, so they are lowercased,
/// trimmed, stripped of a leading '#', deduplicated and sorted on the way in.
List<String> normaliseTags(Iterable<String> tags) {
  final cleaned = tags
      .map((tag) => tag.trim().toLowerCase().replaceFirst(RegExp(r'^#+'), ''))
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList();
  cleaned.sort();
  return cleaned;
}

/// One occurrence of a library item inside a container. Has its own id so a
/// container can hold two of the same thing in different places.
class ContainerEntry {
  const ContainerEntry({required this.id, required this.itemId});

  final String id;
  final String itemId;

  Map<String, dynamic> toJson() => {'id': id, 'itemId': itemId};

  factory ContainerEntry.fromJson(Map<String, dynamic> json) => ContainerEntry(
    id: json['id'] as String,
    itemId: json['itemId'] as String,
  );
}

/// A bag, box, pouch or pocket, and what you want to get into it.
class GearContainer {
  const GearContainer({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.depth,
    required this.colorValue,
    this.tolerance = 0,
    this.entries = const [],
    this.placements = const {},
  });

  final String id;
  final String name;
  final double width;
  final double height;
  final double? depth;
  final int colorValue;

  /// Minimum gap kept clear of every wall and between any two pieces of gear.
  /// Zero means gear may sit flush.
  final double tolerance;

  final List<ContainerEntry> entries;

  /// Placements by *entry* id. An entry with no placement is not packed.
  final Map<String, Placement> placements;

  Color get color => Color(colorValue);

  bool get hasDepth => depth != null;

  double get area => width * height;

  double? get volume => depth == null ? null : width * height * depth!;

  GearContainer copyWith({
    String? name,
    double? width,
    double? height,
    double? depth,
    bool clearDepth = false,
    int? colorValue,
    double? tolerance,
    List<ContainerEntry>? entries,
    Map<String, Placement>? placements,
  }) => GearContainer(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    depth: clearDepth ? null : (depth ?? this.depth),
    colorValue: colorValue ?? this.colorValue,
    tolerance: tolerance ?? this.tolerance,
    entries: entries ?? this.entries,
    placements: placements ?? this.placements,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    if (depth != null) 'depth': depth,
    'colorValue': colorValue,
    'tolerance': tolerance,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'placements': placements.map(
      (entryId, placement) => MapEntry(entryId, placement.toJson()),
    ),
  };

  factory GearContainer.fromJson(Map<String, dynamic> json) {
    final rawPlacements = json['placements'] as Map<String, dynamic>? ?? {};
    return GearContainer(
      id: json['id'] as String,
      name: json['name'] as String,
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      depth: (json['depth'] as num?)?.toDouble(),
      colorValue: json['colorValue'] as int,
      tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0,
      entries: (json['entries'] as List<dynamic>? ?? [])
          .map((entry) => ContainerEntry.fromJson(entry as Map<String, dynamic>))
          .toList(),
      placements: rawPlacements.map(
        (entryId, placement) => MapEntry(
          entryId,
          Placement.fromJson(placement as Map<String, dynamic>),
        ),
      ),
    );
  }
}

/// A named set of library items — a kit you pack again and again.
class Recipe {
  const Recipe({required this.id, required this.name, this.itemIds = const []});

  final String id;
  final String name;

  /// May contain the same item twice, meaning "pack two of these".
  final List<String> itemIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'itemIds': itemIds,
  };

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
    id: json['id'] as String,
    name: json['name'] as String,
    itemIds: (json['itemIds'] as List<dynamic>? ?? [])
        .map((id) => id as String)
        .toList(),
  );
}

/// App-wide preferences.
class AppSettings {
  const AppSettings({
    this.unitId = 'centimetres',
    this.defaultTolerance = 0,
  });

  /// Either a built-in unit's id or a [CustomUnit]'s. Held as an id rather than
  /// a unit so a custom unit stays resolvable after its length changes.
  final String unitId;

  /// Tolerance given to newly created containers, in centimetres.
  final double defaultTolerance;

  AppSettings copyWith({String? unitId, double? defaultTolerance}) =>
      AppSettings(
        unitId: unitId ?? this.unitId,
        defaultTolerance: defaultTolerance ?? this.defaultTolerance,
      );

  Map<String, dynamic> toJson() => {
    'unitId': unitId,
    'defaultTolerance': defaultTolerance,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    // 'unit' is what the first release wrote, and held the same ids.
    unitId:
        json['unitId'] as String? ?? json['unit'] as String? ?? 'centimetres',
    defaultTolerance: (json['defaultTolerance'] as num?)?.toDouble() ?? 0,
  );
}

/// A container entry with its library item resolved.
class PlanEntry {
  const PlanEntry({
    required this.id,
    required this.item,
    required this.placement,
  });

  /// The container entry id — what placements are keyed by.
  final String id;
  final GearItem item;
  final Placement? placement;

  bool get isPacked => placement != null;
}

/// A container with its gear resolved from the library. This is what the
/// packer and the diagram work with; [GearContainer] alone only knows ids.
class Plan {
  const Plan({required this.container, required this.entries});

  final GearContainer container;
  final List<PlanEntry> entries;

  String get id => container.id;
  String get name => container.name;
  double get tolerance => container.tolerance;

  /// The plan is three-dimensional only when the container and at least one
  /// piece of gear carry a depth. Otherwise the side view has nothing to show.
  bool get isThreeDimensional =>
      container.hasDepth && entries.any((entry) => entry.item.hasDepth);

  /// The depth axis the packer works in — a nominal 1 cm for flat plans, so
  /// the same three-dimensional code handles both.
  double get workingDepth =>
      isThreeDimensional ? container.depth! : 1.0;

  List<PlanEntry> get packed => entries.where((e) => e.isPacked).toList();

  List<PlanEntry> get unpacked => entries.where((e) => !e.isPacked).toList();

  /// Fraction of the container's floor area covered by packed gear.
  double get areaUsed {
    if (container.area <= 0) return 0;
    final used = packed.fold<double>(0, (sum, e) => sum + e.item.area);
    return used / container.area;
  }

  /// Fraction of container volume used, or null when this is a flat plan.
  double? get volumeUsed {
    final total = container.volume;
    if (total == null || total <= 0) return null;
    final used = packed.fold<double>(0, (sum, e) => sum + e.item.volume);
    return used / total;
  }

  PlanEntry? entryById(String entryId) {
    for (final entry in entries) {
      if (entry.id == entryId) return entry;
    }
    return null;
  }
}

/// The palette gear and containers are coloured from. Kept small so a plan
/// stays readable — the point is telling shapes apart, not decoration.
const List<int> kGearPalette = [
  0xFF3B82F6, // blue
  0xFFF59E0B, // amber
  0xFF10B981, // emerald
  0xFFEF4444, // red
  0xFF8B5CF6, // violet
  0xFFEC4899, // pink
  0xFF14B8A6, // teal
  0xFF84CC16, // lime
  0xFFF97316, // orange
  0xFF6366F1, // indigo
];
