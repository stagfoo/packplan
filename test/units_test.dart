import 'package:flutter_test/flutter_test.dart';
import 'package:packplan/units.dart';

void main() {
  group('conversion', () {
    test('centimetres are the identity', () {
      expect(MeasurementUnit.centimetres.toCentimetres(32), 32);
      expect(MeasurementUnit.centimetres.fromCentimetres(32), 32);
    });

    test('millimetres are a tenth of a centimetre', () {
      expect(MeasurementUnit.millimetres.toCentimetres(320), 32);
      expect(MeasurementUnit.millimetres.fromCentimetres(32), 320);
    });

    test('inches convert at 2.54', () {
      expect(MeasurementUnit.inches.toCentimetres(1), closeTo(2.54, 1e-9));
      expect(
        MeasurementUnit.inches.fromCentimetres(2.54),
        closeTo(1, 1e-9),
      );
    });

    test('a round trip through any unit is lossless', () {
      for (final unit in MeasurementUnit.builtIns) {
        expect(
          unit.toCentimetres(unit.fromCentimetres(37.5)),
          closeTo(37.5, 1e-9),
        );
      }
    });
  });

  group('formatting', () {
    test('drops the trailing zero on whole numbers', () {
      expect(MeasurementUnit.centimetres.format(32), '32');
      expect(MeasurementUnit.centimetres.format(32.5), '32.5');
    });

    test('rounds centimetres to one decimal', () {
      expect(MeasurementUnit.centimetres.format(32.44), '32.4');
    });

    test('shows millimetres as whole numbers', () {
      expect(MeasurementUnit.millimetres.format(32), '320');
      expect(MeasurementUnit.millimetres.format(32.44), '324');
    });

    test('shows inches to one decimal', () {
      expect(MeasurementUnit.inches.format(32), '12.6');
    });

    test('appends the symbol when asked', () {
      expect(MeasurementUnit.inches.formatWithSymbol(2.54), '1 in');
    });

    test('joins dimensions, skipping a null depth', () {
      expect(
        formatDimensions(
          MeasurementUnit.centimetres,
          width: 32,
          height: 48,
          depth: 20,
        ),
        '32 × 48 × 20 cm',
      );
      expect(
        formatDimensions(MeasurementUnit.centimetres, width: 20, height: 13),
        '20 × 13 cm',
      );
    });
  });

  group('parsing', () {
    test('reads input in the chosen unit', () {
      expect(MeasurementUnit.millimetres.parseToCentimetres('320'), 32);
      expect(
        MeasurementUnit.inches.parseToCentimetres('1'),
        closeTo(2.54, 1e-9),
      );
    });

    test('tolerates surrounding whitespace', () {
      expect(MeasurementUnit.centimetres.parseToCentimetres(' 32 '), 32);
    });

    test('returns null for nonsense', () {
      expect(MeasurementUnit.centimetres.parseToCentimetres('abc'), isNull);
      expect(MeasurementUnit.centimetres.parseToCentimetres(''), isNull);
    });
  });

  group('persistence of the choice', () {
    test('built-ins round trip by id', () {
      for (final unit in MeasurementUnit.builtIns) {
        expect(MeasurementUnit.builtInById(unit.id), unit);
      }
    });

    test('an unrecognised id is not a built-in', () {
      expect(MeasurementUnit.builtInById(null), isNull);
      expect(MeasurementUnit.builtInById('furlongs'), isNull);
    });
  });

  group('custom units', () {
    test('a free-form unit measures by its own length', () {
      const hand = CustomUnit(id: 'u1', name: 'hand', centimetres: 19);
      final unit = hand.resolve();

      expect(unit.symbol, 'hand');
      expect(unit.centimetresPerUnit, 19);
      expect(unit.format(38), '2');
      expect(unit.formatWithSymbol(19), '1 hand');
    });

    test('a derived unit takes its length from the live gear', () {
      const notebook = CustomUnit(
        id: 'u2',
        name: 'notebook',
        centimetres: 21,
        sourceItemId: 'item-1',
        sourceAxis: GearAxis.height,
      );

      // Re-measuring the notebook recalibrates everything measured with it.
      expect(notebook.resolve(liveLength: 20).centimetresPerUnit, 20);
      expect(notebook.resolve(liveLength: 20).format(40), '2');
    });

    test('a derived unit falls back to its captured length', () {
      const notebook = CustomUnit(
        id: 'u2',
        name: 'notebook',
        centimetres: 21,
        sourceItemId: 'item-1',
        sourceAxis: GearAxis.height,
      );

      expect(notebook.resolve().centimetresPerUnit, 21);
    });

    test('a length at or below zero is clamped, never infinite', () {
      const broken = CustomUnit(id: 'u3', name: 'nothing', centimetres: 0);

      expect(
        broken.resolve().centimetresPerUnit,
        greaterThanOrEqualTo(kMinimumUnitLength),
      );
      expect(broken.resolve().format(10).contains('Infinity'), isFalse);
    });

    test('round trips through JSON', () {
      const original = CustomUnit(
        id: 'u4',
        name: 'boot',
        centimetres: 29.5,
        sourceItemId: 'item-9',
        sourceAxis: GearAxis.width,
      );

      final restored = CustomUnit.fromJson(original.toJson());

      expect(restored.id, 'u4');
      expect(restored.name, 'boot');
      expect(restored.centimetres, 29.5);
      expect(restored.sourceItemId, 'item-9');
      expect(restored.sourceAxis, GearAxis.width);
      expect(restored.isDerived, isTrue);
    });

    test('a free-form unit round trips without a source', () {
      const original = CustomUnit(id: 'u5', name: 'hand', centimetres: 19);
      final restored = CustomUnit.fromJson(original.toJson());

      expect(restored.sourceItemId, isNull);
      expect(restored.isDerived, isFalse);
    });
  });
}
