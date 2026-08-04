// Everything is stored in centimetres. Units are a display and input concern
// only — nothing downstream of a text field ever sees anything else, which
// keeps the packer and the saved file free of unit bugs.

/// Which dimension of a piece of gear a derived unit measures by.
enum GearAxis {
  width('Width'),
  height('Height'),
  depth('Depth');

  const GearAxis(this.label);

  final String label;

  static GearAxis fromName(String? name) => GearAxis.values.firstWhere(
    (axis) => axis.name == name,
    orElse: () => GearAxis.height,
  );
}

/// A unit of length. Built-in units are the three below; anything else is a
/// [CustomUnit] the user defined.
class MeasurementUnit {
  const MeasurementUnit({
    required this.id,
    required this.name,
    required this.symbol,
    required this.centimetresPerUnit,
    this.decimals = 1,
  });

  final String id;
  final String name;

  /// Shown after a number, so it wants to be short.
  final String symbol;

  final double centimetresPerUnit;

  /// How many decimal places are worth showing. Millimetres are already fine
  /// enough that a decimal adds noise.
  final int decimals;

  static const centimetres = MeasurementUnit(
    id: 'centimetres',
    name: 'Centimetres',
    symbol: 'cm',
    centimetresPerUnit: 1,
  );

  static const millimetres = MeasurementUnit(
    id: 'millimetres',
    name: 'Millimetres',
    symbol: 'mm',
    centimetresPerUnit: 0.1,
    decimals: 0,
  );

  static const inches = MeasurementUnit(
    id: 'inches',
    name: 'Inches',
    symbol: 'in',
    centimetresPerUnit: 2.54,
  );

  static const builtIns = [centimetres, millimetres, inches];

  static MeasurementUnit? builtInById(String? id) {
    for (final unit in builtIns) {
      if (unit.id == id) return unit;
    }
    return null;
  }

  double toCentimetres(double value) => value * centimetresPerUnit;

  double fromCentimetres(double centimetres) =>
      centimetres / centimetresPerUnit;

  /// Formats a stored centimetre value in this unit, without the symbol.
  /// Trailing zeroes are dropped so whole numbers read as "32", not "32.0".
  String format(double centimetres) {
    if (centimetresPerUnit <= 0) return '0';
    final value = fromCentimetres(centimetres);
    final rounded = double.parse(value.toStringAsFixed(decimals));
    if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
    return rounded.toStringAsFixed(decimals);
  }

  /// Formats with the unit symbol appended, for standalone labels.
  String formatWithSymbol(double centimetres) =>
      '${format(centimetres)} $symbol';

  /// Parses user input in this unit into centimetres. Returns null when the
  /// text is not a number.
  double? parseToCentimetres(String text) {
    final value = double.tryParse(text.trim());
    if (value == null) return null;
    return toCentimetres(value);
  }

  @override
  bool operator ==(Object other) =>
      other is MeasurementUnit &&
      other.id == id &&
      other.centimetresPerUnit == centimetresPerUnit &&
      other.symbol == symbol;

  @override
  int get hashCode => Object.hash(id, centimetresPerUnit, symbol);
}

/// The smallest length a unit may have. Anything at or below zero would make
/// every measurement infinite.
const double kMinimumUnitLength = 0.01;

/// A unit the user made up — "my hand", or the notebook they always carry.
///
/// When [sourceItemId] is set the length is taken from that piece of gear, so
/// re-measuring the gear re-calibrates the unit. [centimetres] is the length
/// captured when the unit was made, and is what the unit falls back to if the
/// gear is later deleted.
class CustomUnit {
  const CustomUnit({
    required this.id,
    required this.name,
    required this.centimetres,
    this.sourceItemId,
    this.sourceAxis,
  });

  final String id;
  final String name;
  final double centimetres;
  final String? sourceItemId;
  final GearAxis? sourceAxis;

  bool get isDerived => sourceItemId != null;

  /// Builds the unit to measure with. [liveLength] is the source gear's current
  /// dimension, or null when there is no source gear or it has been deleted.
  MeasurementUnit resolve({double? liveLength}) {
    final length = liveLength ?? centimetres;
    return MeasurementUnit(
      id: id,
      name: name,
      symbol: name,
      centimetresPerUnit: length < kMinimumUnitLength
          ? kMinimumUnitLength
          : length,
    );
  }

  CustomUnit copyWith({
    String? name,
    double? centimetres,
    String? sourceItemId,
    GearAxis? sourceAxis,
    bool clearSource = false,
  }) => CustomUnit(
    id: id,
    name: name ?? this.name,
    centimetres: centimetres ?? this.centimetres,
    sourceItemId: clearSource ? null : (sourceItemId ?? this.sourceItemId),
    sourceAxis: clearSource ? null : (sourceAxis ?? this.sourceAxis),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'centimetres': centimetres,
    if (sourceItemId != null) 'sourceItemId': sourceItemId,
    if (sourceAxis != null) 'sourceAxis': sourceAxis!.name,
  };

  factory CustomUnit.fromJson(Map<String, dynamic> json) => CustomUnit(
    id: json['id'] as String,
    name: json['name'] as String,
    centimetres: (json['centimetres'] as num).toDouble(),
    sourceItemId: json['sourceItemId'] as String?,
    sourceAxis: json['sourceAxis'] == null
        ? null
        : GearAxis.fromName(json['sourceAxis'] as String),
  );
}

/// Joins dimensions into "32 × 48 × 20 cm", skipping a null depth.
String formatDimensions(
  MeasurementUnit unit, {
  required double width,
  required double height,
  double? depth,
}) {
  final parts = [
    unit.format(width),
    unit.format(height),
    if (depth != null) unit.format(depth),
  ];
  return '${parts.join(' × ')} ${unit.symbol}';
}
