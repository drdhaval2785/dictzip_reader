import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'source.dart';

/// Parses and reads from a dictzip (`.dict.dz`) file without fully decompressing it.
///
/// Dictzip is a gzip variant that stores a Random Access (RA) chunk index in
/// the gzip Extra Field. The uncompressed data is divided into fixed-size
/// chunks (CHLEN bytes each), each chunk independently deflated. This allows
/// efficient random access: only the chunk(s) covering the requested byte
/// range need to be decompressed.
///
/// Usage:
/// ```dart
/// final reader = DictzipReader('/path/to/file.dict.dz');
/// await reader.open();
/// final text = await reader.read(offset, length);
/// await reader.close();
/// ```
class DictzipReader {
  final String? path;
  RandomAccessSource? _source;

  /// Uncompressed size of each chunk (CHLEN from RA header).
  int _chunkLen = 0;

  /// Compressed size of each chunk (from RA header).
  late List<int> _chunkCompressedSizes;

  /// Cumulative byte offsets into the file for each chunk's compressed data.
  late List<int> _chunkFileOffsets;

  /// File position where the first compressed chunk begins (after gzip header).
  int _dataOffset = 0;

  bool _opened = false;

  /// Current position in the source during header parsing.
  int _currentPos = 0;

  DictzipReader(this.path);

  // ---------------------------------------------------------------------------
  // Open / Close
  // ---------------------------------------------------------------------------

  /// Opens the file and parses the dictzip header.
  ///
  /// Must be called before [read].
  Future<void> open() async {
    if (path == null) throw StateError('Path is null. Use openSource() instead.');
    _source = FileRandomAccessSource(path!);
    await _parseHeader();
    _opened = true;
  }

  /// Opens the reader with a custom [RandomAccessSource].
  Future<void> openSource(RandomAccessSource source) async {
    _source = source;
    await _parseHeader();
    _opened = true;
  }

  /// Closes the file.
  Future<void> close() async {
    await _source?.close();
    _source = null;
    _opened = false;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Reads [length] bytes starting at uncompressed [offset], returning UTF-8 text.
  ///
  /// Decompresses only the chunks that overlap the requested range.
  Future<String> read(int offset, int length) async {
    final bytes = await readBytes(offset, length);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Reads [length] bytes starting at uncompressed [offset], returning the raw bytes.
  ///
  /// Decompresses only the chunks that overlap the requested range.
  Future<List<int>> readBytes(int offset, int length) async {
    if (!_opened) throw StateError('DictzipReader not opened. Call open() first.');
    return _readBytes(offset, length);
  }

  /// Reads multiple byte ranges in a single pass to minimize I/O and decompression.
  ///
  /// Processing is done linearly by sorting queries by offset.
  /// Takes a list of (offset, length) tuples and returns a list of byte arrays.
  Future<List<List<int>>> readBulkBytes(List<(int offset, int length)> queries) async {
    if (!_opened) throw StateError('DictzipReader not opened. Call open() first.');
    if (queries.isEmpty) return [];

    // Tag queries with original index to preserve output order.
    final indexedQueries = List.generate(queries.length, (i) {
      final q = queries[i];
      return (
        index: i,
        offset: q.$1,
        length: q.$2,
        firstChunk: q.$1 ~/ _chunkLen,
        lastChunk: q.$2 <= 0 ? (q.$1 ~/ _chunkLen) : ((q.$1 + q.$2 - 1) ~/ _chunkLen),
      );
    });

    // Sort by offset to process chunks linearly.
    final sortedQueries = List.of(indexedQueries)..sort((a, b) => a.offset.compareTo(b.offset));

    final results = List<List<int>>.filled(queries.length, const []);
    final activeQueries = <_ActiveQuery>[];
    int nextQueryIdx = 0;

    // Find the range of chunks we need to visit.
    int? minChunk;
    int? maxChunk;
    for (final q in sortedQueries) {
      if (q.length <= 0) {
        results[q.index] = const [];
        continue;
      }
      minChunk = (minChunk == null) ? q.firstChunk : (q.firstChunk < minChunk ? q.firstChunk : minChunk);
      maxChunk = (maxChunk == null) ? q.lastChunk : (q.lastChunk > maxChunk ? q.lastChunk : maxChunk);
    }

    if (minChunk == null || maxChunk == null) return results;

    for (int ci = minChunk; ci <= maxChunk; ci++) {
      // Add queries that start in this chunk to active list.
      while (nextQueryIdx < sortedQueries.length && sortedQueries[nextQueryIdx].firstChunk == ci) {
        final q = sortedQueries[nextQueryIdx];
        if (q.length > 0) {
          activeQueries.add(_ActiveQuery(
            index: q.index,
            offset: q.offset,
            length: q.length,
            buffer: Uint8List(q.length),
            bytesRead: 0,
          ));
        }
        nextQueryIdx++;
      }

      if (activeQueries.isEmpty) continue;

      // Decompress the current chunk once.
      final chunkData = await _decompressChunk(ci);

      // For each active query, copy relevant data from this chunk.
      for (int i = activeQueries.length - 1; i >= 0; i--) {
        final aq = activeQueries[i];

        // Position in the uncompressed stream where this chunk starts.
        final int chunkOffset = ci * _chunkLen;
        
        // Calculate where in the chunk we should start reading for this query.
        // It's either the query's start offset (if this is its first chunk) 
        // or the start of the chunk.
        final int startInChunk = (aq.bytesRead == 0) 
            ? (aq.offset - chunkOffset) 
            : 0;

        final int remainingInQuery = aq.length - aq.bytesRead;
        final int availableInChunk = chunkData.length - startInChunk;

        if (availableInChunk <= 0) {
          // Chunk is shorter than expected or query offset is beyond chunk end.
          results[aq.index] = aq.buffer.sublist(0, aq.bytesRead);
          activeQueries.removeAt(i);
          continue;
        }

        final int bytesToCopy = remainingInQuery < availableInChunk ? remainingInQuery : availableInChunk;

        aq.buffer.setRange(aq.bytesRead, aq.bytesRead + bytesToCopy, chunkData.sublist(startInChunk, startInChunk + bytesToCopy));
        aq.bytesRead += bytesToCopy;

        if (aq.bytesRead >= aq.length) {
          results[aq.index] = aq.buffer;
          activeQueries.removeAt(i);
        }
      }
    }

    // Handle any queries that didn't finish (e.g. EOF reached before length satisfied).
    for (final aq in activeQueries) {
      results[aq.index] = aq.buffer.sublist(0, aq.bytesRead);
    }

    return results;
  }

  /// Reads multiple byte ranges and decodes them as UTF-8 strings.
  Future<List<String>> readBulk(List<(int offset, int length)> queries) async {
    final byteResults = await readBulkBytes(queries);
    return byteResults.map((bytes) => utf8.decode(bytes, allowMalformed: true)).toList();
  }

  // ---------------------------------------------------------------------------
  // Header Parsing
  // ---------------------------------------------------------------------------

  /// Reads the gzip header from the file and extracts dictzip RA metadata.
  ///
  /// Gzip header layout (RFC 1952):
  ///   0-1   ID magic   (0x1f, 0x8b)
  ///   2     CM         (must be 8 = deflate)
  ///   3     FLG        (flags)
  ///   4-7   MTIME
  ///   8     XFL
  ///   9     OS
  ///   if FLG.FEXTRA (bit 2):
  ///     10-11  XLEN (LE uint16)
  ///     12..   extra field (contains RA subfield)
  ///   if FLG.FNAME  (bit 3): null-terminated string
  ///   if FLG.FCOMMENT (bit 4): null-terminated string
  ///   if FLG.FHCRC (bit 1): 2-byte CRC
  /// → data starts here
  Future<void> _parseHeader() async {
    final source = _source!;
    _currentPos = 0;

    // Read the first 10 bytes (fixed gzip header).
    final header = await source.read(_currentPos, 10);
    _currentPos += 10;

    if (header.length < 10) throw FormatException('File too short to be a valid gzip/dictzip file.');
    if (header[0] != 0x1f || header[1] != 0x8b) {
      throw FormatException('Not a gzip file (bad magic bytes): ${path ?? 'source'}');
    }
    // header[2] = CM (8 = deflate) — we don't enforce this to be lenient.
    final flags = header[3];

    const flagFHCRC    = 0x02;
    const flagFEXTRA   = 0x04;
    const flagFNAME    = 0x08;
    const flagFCOMMENT = 0x10;

    // ── FEXTRA ────────────────────────────────────────────────────────────────
    if (flags & flagFEXTRA != 0) {
      final xlenBytes = await source.read(_currentPos, 2);
      _currentPos += 2;
      final xlen = ByteData.sublistView(Uint8List.fromList(xlenBytes)).getUint16(0, Endian.little);
      final extraBytes = await source.read(_currentPos, xlen);
      _currentPos += xlen;
      _parseExtraField(Uint8List.fromList(extraBytes));
    }

    // ── FNAME ─────────────────────────────────────────────────────────────────
    if (flags & flagFNAME != 0) {
      await _skipNullTerminated();
    }

    // ── FCOMMENT ──────────────────────────────────────────────────────────────
    if (flags & flagFCOMMENT != 0) {
      await _skipNullTerminated();
    }

    // ── FHCRC ─────────────────────────────────────────────────────────────────
    if (flags & flagFHCRC != 0) {
      await source.read(_currentPos, 2); // skip CRC16
      _currentPos += 2;
    }

    _dataOffset = _currentPos;

    if (_chunkLen == 0) {
      throw FormatException('Not a dictzip file: missing RA extra subfield in ${path ?? 'source'}');
    }

    // Build cumulative file offsets for each chunk.
    _chunkFileOffsets = List<int>.filled(_chunkCompressedSizes.length + 1, 0);
    int pos = _dataOffset;
    for (int i = 0; i < _chunkCompressedSizes.length; i++) {
      _chunkFileOffsets[i] = pos;
      pos += _chunkCompressedSizes[i];
    }
    _chunkFileOffsets[_chunkCompressedSizes.length] = pos;
  }

  /// Parses the gzip Extra Field, looking for the 'RA' (Random Access) subfield.
  ///
  /// Extra field consists of variable-length subfields:
  ///   2 bytes  SI1, SI2  (subfield ID)
  ///   2 bytes  LEN (LE uint16)
  ///   LEN bytes data
  ///
  /// The RA subfield data:
  ///   2 bytes  version   (must be 1)
  ///   2 bytes  CHLEN     (uncompressed chunk size, LE uint16)
  ///   2 bytes  CHCNT     (number of chunks, LE uint16)
  ///   CHCNT × 2 bytes  compressed size of each chunk (LE uint16)
  void _parseExtraField(Uint8List extra) {
    int i = 0;
    while (i + 4 <= extra.length) {
      final si1 = extra[i];
      final si2 = extra[i + 1];
      final subLen = ByteData.sublistView(extra, i + 2, i + 4).getUint16(0, Endian.little);
      i += 4;

      if (si1 == 0x52 && si2 == 0x41) {
        // 'R' = 0x52, 'A' = 0x41 — this is the RA subfield.
        if (i + 6 > extra.length) break;
        final bd = ByteData.sublistView(extra, i, i + subLen);
        // version = bd.getUint16(0, Endian.little); // typically 1
        _chunkLen  = bd.getUint16(2, Endian.little);
        final chcnt = bd.getUint16(4, Endian.little);
        _chunkCompressedSizes = List<int>.filled(chcnt, 0);
        for (int c = 0; c < chcnt; c++) {
          _chunkCompressedSizes[c] = bd.getUint16(6 + c * 2, Endian.little);
        }
        return;
      }

      i += subLen;
    }
    // RA subfield not found — _chunkLen remains 0, caller will throw.
  }

  /// Skips bytes until a null byte (0x00) is consumed.
  Future<void> _skipNullTerminated() async {
    final source = _source!;
    while (true) {
      final chunk = await source.read(_currentPos, 64);
      if (chunk.isEmpty) break;
      
      final nullIndex = chunk.indexOf(0);
      if (nullIndex != -1) {
        _currentPos += nullIndex + 1;
        break;
      }
      _currentPos += chunk.length;
    }
  }

  // ---------------------------------------------------------------------------
  // Chunk-based reading
  // ---------------------------------------------------------------------------

  Future<List<int>> _readBytes(int offset, int length) async {
    if (length <= 0) return [];

    final firstChunk = offset ~/ _chunkLen;
    final lastChunk  = (offset + length - 1) ~/ _chunkLen;

    // Decompress all needed chunks into a contiguous buffer.
    final buffer = <int>[];
    for (int ci = firstChunk; ci <= lastChunk; ci++) {
      buffer.addAll(await _decompressChunk(ci));
    }

    // Slice out the requested range.
    final startInBuffer = offset - firstChunk * _chunkLen;
    final end = startInBuffer + length;
    if (end > buffer.length) {
      // Clamp gracefully if the file is shorter than expected.
      return buffer.sublist(startInBuffer, buffer.length);
    }
    return buffer.sublist(startInBuffer, end);
  }

  Future<List<int>> _decompressChunk(int chunkIndex) async {
    if (chunkIndex >= _chunkCompressedSizes.length) return [];

    final fileOffset  = _chunkFileOffsets[chunkIndex];
    final compressed  = _chunkCompressedSizes[chunkIndex];

    final raw = await _source!.read(fileOffset, compressed);

    // Raw inflate — no gzip / zlib header, just deflate stream.
    return ZLibDecoder(raw: true).convert(raw);
  }
}

/// Helper class to track the progress of a bulk read query.
class _ActiveQuery {
  final int index;
  final int offset;
  final int length;
  final Uint8List buffer;
  int bytesRead;

  _ActiveQuery({
    required this.index,
    required this.offset,
    required this.length,
    required this.buffer,
    required this.bytesRead,
  });
}
