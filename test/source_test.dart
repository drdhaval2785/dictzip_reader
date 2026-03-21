import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dictzip_reader/dictzip_reader.dart';
import 'dart:io';

class MemoryRandomAccessSource implements RandomAccessSource {
  final Uint8List data;
  bool closed = false;

  MemoryRandomAccessSource(this.data);

  @override
  Future<int> get length async => data.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset >= data.length) return Uint8List(0);
    final end = offset + length > data.length ? data.length : offset + length;
    return data.sublist(offset, end);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  group('DictzipReader with RandomAccessSource', () {
    const testFilePath = 'test_assets/test.dict.dz';
    
    test('should work with MemoryRandomAccessSource', () async {
      final fileData = await File(testFilePath).readAsBytes();
      final source = MemoryRandomAccessSource(fileData);
      final reader = DictzipReader(null);
      
      await reader.openSource(source);
      
      final text = await reader.read(0, 14);
      expect(text, equals('Hello Dictzip!'));
      
      await reader.close();
      expect(source.closed, isTrue);
    });

    test('should work with FileRandomAccessSource via openSource', () async {
      final source = FileRandomAccessSource(testFilePath);
      final reader = DictzipReader(null);
      
      await reader.openSource(source);
      
      final text = await reader.read(0, 14);
      expect(text, equals('Hello Dictzip!'));
      
      await reader.close();
    });
  });
}
