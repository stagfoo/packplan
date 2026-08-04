import 'dart:ui' show Color;

/// Everything in the app is measured in centimetres. Dimensions are stored as
/// doubles because gear rarely lands on whole numbers.

/// Where the packer (or the user) decided a good should sit, in container
/// coordinates. `z` is the depth axis and stays 0 for flat plans.
class Placement {
  const Placement({
    required this.goodId,
    required this.x,
    required this.y,
    required this.z,
    required this.width,
    required this.height,
    required this.depth,
  });

  final String goodId;

  final double x;
  final double y;
  final double z;

  /// The good's dimensions *as placed* — the packer is allowed to rotate
  /// goods, so these may be a permutation of the good's own dimensions.
  final double width;
  final double height;
  final double depth;

  double get right => x + width;
  double get bottom => y + height;
  double get back => z + depth;

  Placement copyWith({double? x, double? y, double? z}) => Placement(
    goodId: goodId,
    x: x ?? this.x,
    y: y ?? this.y,
    z: z ?? this.z,
    width: width,
    height: height,
    depth: depth,
  );

  /// True when this placement shares volume with [other]. Touching faces do
  /// not count as overlapping.
  bool overlaps(Placement other) {
    return x < other.right &&
        other.x < right &&
        y < other.bottom &&
        other.y < bottom &&
        z < other.back &&
        other.z < back;
  }

  Map<String, dynamic> toJson() => {
    'goodId': goodId,
    'x': x,
    'y': y,
    'z': z,
    'width': width,
    'height': height,
    'depth': depth,
  };

  factory Placement.fromJson(Map<String, dynamic> json) => Placement(
    goodId: json['goodId'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    depth: (json['depth'] as num).toDouble(),
  );
}

/// A single piece of gear.
class Good {
  const Good({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.depth,
    required this.colorValue,
    this.rotatable = true,
  });

  final String id;
  final String name;
  final double width;
  final double height;

  /// Optional — a good without depth is treated as flat, and only shows up in
  /// the front view.
  final double? depth;

  final int colorValue;

  /// Whether the packer may turn this good to make it fit. Some gear only
  /// packs one way up.
  final bool rotatable;

  Color get color => Color(colorValue);

  bool get hasDepth => depth != null;

  double get area => width * height;

  Good copyWith({
    String? name,
    double? width,
    double? height,
    double? depth,
    bool clearDepth = false,
    int? colorValue,
    bool? rotatable,
  }) => Good(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    depth: clearDepth ? null : (depth ?? this.depth),
    colorValue: colorValue ?? this.colorValue,
    rotatable: rotatable ?? this.rotatable,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    if (depth != null) 'depth': depth,
    'colorValue': colorValue,
    'rotatable': rotatable,
  };

  factory Good.fromJson(Map<String, dynamic> json) => Good(
    id: json['id'] as String,
    name: json['name'] as String,
    width: (json['width'] as num).toDouble(),
    height: (json['height'] as num).toDouble(),
    depth: (json['depth'] as num?)?.toDouble(),
    colorValue: json['colorValue'] as int,
    rotatable: json['rotatable'] as bool? ?? true,
  );
}

/// A bag, box, pouch or pocket, plus the gear you want to get into it.
class GearContainer {
  const GearContainer({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.depth,
    required this.colorValue,
    this.goods = const [],
    this.placements = const {},
  });

  final String id;
  final String name;
  final double width;
  final double height;
  final double? depth;
  final int colorValue;
  final List<Good> goods;

  /// Placements by good id. A good with no entry here did not fit (or has not
  /// been packed yet).
  final Map<String, Placement> placements;

  Color get color => Color(colorValue);

  bool get hasDepth => depth != null;

  /// The plan is three-dimensional only when the container and at least one
  /// good carry a depth. Otherwise the side view has nothing to show.
  bool get isThreeDimensional =>
      hasDepth && goods.any((good) => good.hasDepth);

  double get area => width * height;

  double? get volume => depth == null ? null : width * height * depth!;

  List<Good> get packedGoods =>
      goods.where((good) => placements.containsKey(good.id)).toList();

  List<Good> get unpackedGoods =>
      goods.where((good) => !placements.containsKey(good.id)).toList();

  /// Fraction of the container's floor area covered by packed goods, 0..1+.
  double get areaUsed {
    if (area <= 0) return 0;
    final used = packedGoods.fold<double>(0, (sum, good) => sum + good.area);
    return used / area;
  }

  /// Fraction of container volume used, or null when this is a flat plan.
  double? get volumeUsed {
    final total = volume;
    if (total == null || total <= 0) return null;
    final used = packedGoods.fold<double>(
      0,
      (sum, good) => sum + good.width * good.height * (good.depth ?? 0),
    );
    return used / total;
  }

  GearContainer copyWith({
    String? name,
    double? width,
    double? height,
    double? depth,
    bool clearDepth = false,
    int? colorValue,
    List<Good>? goods,
    Map<String, Placement>? placements,
  }) => GearContainer(
    id: id,
    name: name ?? this.name,
    width: width ?? this.width,
    height: height ?? this.height,
    depth: clearDepth ? null : (depth ?? this.depth),
    colorValue: colorValue ?? this.colorValue,
    goods: goods ?? this.goods,
    placements: placements ?? this.placements,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'width': width,
    'height': height,
    if (depth != null) 'depth': depth,
    'colorValue': colorValue,
    'goods': goods.map((good) => good.toJson()).toList(),
    'placements': placements.map(
      (goodId, placement) => MapEntry(goodId, placement.toJson()),
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
      goods: (json['goods'] as List<dynamic>? ?? [])
          .map((good) => Good.fromJson(good as Map<String, dynamic>))
          .toList(),
      placements: rawPlacements.map(
        (goodId, placement) => MapEntry(
          goodId,
          Placement.fromJson(placement as Map<String, dynamic>),
        ),
      ),
    );
  }
}

/// The palette goods and containers are coloured from. Kept small so a plan
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
