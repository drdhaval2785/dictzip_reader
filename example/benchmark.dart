import 'dart:io';
import 'package:dictzip_reader/dictzip_reader.dart';

void main() async {
  const path = 'test_assets/test.dict.dz';
  if (!File(path).existsSync()) {
    print('Please ensure test_assets/test.dict.dz exists.');
    return;
  }

  final reader = DictzipReader(path);
  await reader.open();

  const count = 500;
  // Generate 500 random-ish queries within the file
  // Test file size is roughly 15000 bytes (1000 * "Hello Dictzip! ")
  final queries = List.generate(count, (i) => (i * 25, 15));

  print('Comparative Analysis: Reading $count entries');
  print('-------------------------------------------');

  // Benchmark Individual Method
  final watchIndividual = Stopwatch()..start();
  final individualResults = <String>[];
  for (final q in queries) {
    individualResults.add(await reader.read(q.$1, q.$2));
  }
  watchIndividual.stop();
  print('Individual Method: ${watchIndividual.elapsedMilliseconds}ms');

  // Benchmark Bulk Method
  final watchBulk = Stopwatch()..start();
  final bulkResults = await reader.readBulk(queries);
  watchBulk.stop();
  print('Bulk Method:       ${watchBulk.elapsedMilliseconds}ms');

  // Verification
  bool match = true;
  for (int i = 0; i < count; i++) {
    if (individualResults[i] != bulkResults[i]) {
      match = false;
      break;
    }
  }
  print('Results Match:     $match');
  print('Speedup:           ${(watchIndividual.elapsedMilliseconds / watchBulk.elapsedMilliseconds).toStringAsFixed(2)}x');

  await reader.close();
}
