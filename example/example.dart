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
    
    // Read the first 50 bytes
    final text = await reader.read(0, 50);
    print('First 50 bytes: $text');
    
  } catch (e) {
    print('Error: $e');
  } finally {
    await reader.close();
  }
}
