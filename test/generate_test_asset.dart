import 'dart:io';
import 'dart:typed_data';

void main() async {
  final content = 'Hello Dictzip! ' * 1000; // Total 15,000 bytes
  final bytes = Uint8List.fromList(content.codeUnits);
  
  final CHLEN = 100; // Small chunk length for testing
  final chunks = <Uint8List>[];
  for (var i = 0; i < bytes.length; i += CHLEN) {
    var end = i + CHLEN;
    if (end > bytes.length) end = bytes.length;
    chunks.add(Uint8List.sublistView(bytes, i, end));
  }
  
  // Use dart:io ZLibEncoder for raw deflate
  final encoder = ZLibEncoder(gzip: false, raw: true, level: ZLibOption.defaultLevel);
  final compressedChunksRaw = chunks.map((c) => Uint8List.fromList(encoder.convert(c))).toList();

  // Gzip header (10 bytes)
  final header = Uint8List(10);
  header[0] = 0x1f;
  header[1] = 0x8b;
  header[2] = 8; // Deflate
  header[3] = 0x04; // FEXTRA flag
  
  // Build RA extra field
  final chcnt = compressedChunksRaw.length;
  final subLen = 6 + chcnt * 2;
  final extraData = Uint8List(4 + subLen);
  extraData[0] = 0x52; // R
  extraData[1] = 0x41; // A
  extraData[2] = subLen & 0xff;
  extraData[3] = (subLen >> 8) & 0xff;
  
  extraData[4] = 1; // version low
  extraData[5] = 0; // version high
  extraData[6] = CHLEN & 0xff;
  extraData[7] = (CHLEN >> 8) & 0xff;
  extraData[8] = chcnt & 0xff;
  extraData[9] = (chcnt >> 8) & 0xff;
  
  for (var i = 0; i < chcnt; i++) {
    final clen = compressedChunksRaw[i].length;
    extraData[10 + i * 2] = clen & 0xff;
    extraData[11 + i * 2] = (clen >> 8) & 0xff;
  }
  
  final xlen = extraData.length;
  final xlenBytes = Uint8List(2);
  xlenBytes[0] = xlen & 0xff;
  xlenBytes[1] = (xlen >> 8) & 0xff;
  
  final file = File('test_assets/test.dict.dz');
  final raf = file.openSync(mode: FileMode.write);
  raf.writeFromSync(header);
  raf.writeFromSync(xlenBytes);
  raf.writeFromSync(extraData);
  for (final chunk in compressedChunksRaw) {
    raf.writeFromSync(chunk);
  }
  
  raf.writeFromSync(Uint8List(8)); // Dummy Gzip footer
  raf.closeSync();
  
  print('Generated test_assets/test.dict.dz');
}
