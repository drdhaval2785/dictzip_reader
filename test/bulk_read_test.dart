import 'package:test/test.dart';
import 'package:dictzip_reader/dictzip_reader.dart';

void main() {
  group('DictzipReader Bulk Read', () {
    const testFilePath = 'test_assets/test.dict.dz';
    late DictzipReader reader;
    final String fullText = 'Hello Dictzip! ' * 1000;

    setUp(() async {
      reader = DictzipReader(testFilePath);
      await reader.open();
    });

    tearDown(() async {
      await reader.close();
    });

    test('readBulk should return multiple ranges correctly', () async {
      final queries = [
        (0, 14),      // Hello Dictzip!
        (15, 14),     // Hello Dictzip!
        (100, 14),    // Hello Dictzip!
        (85, 30),     // Crosses chunk boundary (chunk len 100)
      ];

      final results = await reader.readBulk(queries);

      expect(results.length, equals(4));
      expect(results[0], equals(fullText.substring(0, 14)));
      expect(results[1], equals(fullText.substring(15, 29)));
      expect(results[2], equals(fullText.substring(100, 114)));
      expect(results[3], equals(fullText.substring(85, 115)));
    });

    test('readBulk should handle overlapping ranges', () async {
      final queries = [
        (0, 20),
        (10, 20),
        (5, 5),
      ];

      final results = await reader.readBulk(queries);

      expect(results[0], equals(fullText.substring(0, 20)));
      expect(results[1], equals(fullText.substring(10, 30)));
      expect(results[2], equals(fullText.substring(5, 10)));
    });

    test('readBulk should handle queries out of order', () async {
      final queries = [
        (100, 10),
        (0, 10),
        (50, 10),
      ];

      final results = await reader.readBulk(queries);

      expect(results[0], equals(fullText.substring(100, 110)));
      expect(results[1], equals(fullText.substring(0, 10)));
      expect(results[2], equals(fullText.substring(50, 60)));
    });

    test('readBulk should handle empty queries list', () async {
      final results = await reader.readBulk([]);
      expect(results, isEmpty);
    });

    test('readBulk should handle zero length queries', () async {
      final results = await reader.readBulk([(10, 0), (0, 0)]);
      expect(results.length, equals(2));
      expect(results[0], isEmpty);
      expect(results[1], isEmpty);
    });

    test('readBulk should handle EOF cases', () async {
      final len = fullText.length;
      final results = await reader.readBulk([(len - 5, 10)]);
      expect(results[0], equals(fullText.substring(len - 5)));
    });
  });
}
