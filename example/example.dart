import 'dart:io';
import 'package:dictzip_reader/dictzip_reader.dart';

void main() async {
  // Replace with a path to a real .dict.dz file for manual testing
  final path = 'test_assets/test.dict.dz';
  
  if (!File(path).existsSync()) {
    print('Please provide a valid .dict.dz file at $path');
    exit(1);
  }

  final reader = DictzipReader(path);
  try {
    await reader.open();
    print('Header parsed successfully.');
    
    // ── Single Read ──────────────────────────────────────────────────────────
    print('\nReading first 50 bytes (single):');
    final text = await reader.read(0, 50);
    print('Result: $text');
    
    // ── Bulk Read ────────────────────────────────────────────────────────────
    print('\nReading multiple ranges in bulk:');
    final queries = [
      (0, 14),   // "Hello Dictzip!"
      (100, 14), // next occurrence
      (200, 14), // next occurrence
    ];
    
    final results = await reader.readBulk(queries);
    for (int i = 0; i < results.length; i++) {
      print('Query $i (offset ${queries[i].$1}): ${results[i]}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    await reader.close();
  }
}
