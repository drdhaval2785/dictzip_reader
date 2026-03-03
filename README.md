# dictzip_reader

A Dart package to read and decompress dictzip (`.dict.dz`) files with random access support.

Dictzip is a gzip variant that stores a Random Access (RA) chunk index in the gzip Extra Field. The uncompressed data is divided into fixed-size chunks, each chunk independently deflated. This allows efficient random access: only the chunk(s) covering the requested byte range need to be decompressed.

## Usage

```dart
import 'package:dictzip_reader/dictzip_reader.dart';

void main() async {
  final reader = DictzipReader('/path/to/file.dict.dz');
  await reader.open();
  
  // Read 100 bytes starting at uncompressed offset 500
  final text = await reader.read(500, 100);
  print(text);
  
  await reader.close();
}
```

## Features

- Parses dictzip RA (Random Access) headers.
- Supports efficient random access to compressed files.
- Handles standard gzip files (though without random access optimization if RA header is missing).
- Low memory footprint by only decompressing necessary chunks.
