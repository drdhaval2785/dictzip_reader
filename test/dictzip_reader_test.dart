import 'dart:io';
import 'package:test/test.dart';
import 'package:dictzip_reader/dictzip_reader.dart';

void main() {
  group('DictzipReader', () {
    const testFilePath = 'test_assets/test.dict.dz';
    late DictzipReader reader;

    setUp(() async {
      reader = DictzipReader(testFilePath);
      await reader.open();
    });

    tearDown(() async {
      await reader.close();
    });

    test('should read the beginning of the file', () async {
      final text = await reader.read(0, 14);
      expect(text, equals('Hello Dictzip!'));
    });

    test('should read across chunk boundaries', () async {
      // Chunk length in test asset is 100.
      // Offset 90 to 110 spans across the first and second chunk.
      final text = await reader.read(85, 30);
      final expected = ('Hello Dictzip! ' * 1000).substring(85, 115);
      expect(text, equals(expected));
    });

    test('should read a range in the middle of a chunk', () async {
      final text = await reader.read(150, 14);
      expect(text, equals('Hello Dictzip!'));
    });

    test('should handle reading more than file length gracefully', () async {
      final fullLength = ('Hello Dictzip! ' * 1000).length;
      final text = await reader.read(fullLength - 10, 100);
      expect(text.length, lessThanOrEqualTo(100));
      expect(text, equals(('Hello Dictzip! ' * 1000).substring(fullLength - 10)));
    });

    test('should throw StateError if reading without opening', () async {
      final unopenedReader = DictzipReader(testFilePath);
      expect(() => unopenedReader.read(0, 10), throwsStateError);
    });

    test('should throw FormatException for non-existent file', () async {
      final badReader = DictzipReader('non_existent.dz');
      expect(() => badReader.open(), throwsA(isA<FileSystemException>()));
    });
  });
}
