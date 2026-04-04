import 'dart:io';
import 'dart:typed_data';

/// Abstract source that provides random-access read capability.
abstract class RandomAccessSource {
  /// Reads [length] bytes starting at [offset].
  Future<Uint8List> read(int offset, int length);

  /// Returns the total size of the data source in bytes.
  Future<int> get length;

  /// Checks and opens the source if necessary.
  Future<void> open() async {}

  /// Releases any system resources (file handles, SAF sessions).
  Future<void> close();
}

/// Default implementation of [RandomAccessSource] using [dart:io].
class FileRandomAccessSource implements RandomAccessSource {
  final String path;
  RandomAccessFile? _file;
  int? _cachedLength;

  FileRandomAccessSource(this.path);

  @override
  Future<void> open() async {
    await _ensureOpen();
  }

  Future<void> _ensureOpen() async {
    if (_file == null) {
      _file = await File(path).open(mode: FileMode.read);
      _cachedLength = await _file!.length();
    }
  }

  @override
  Future<int> get length async {
    await _ensureOpen();
    return _cachedLength!;
  }

  @override
  Future<Uint8List> read(int offset, int length) async {
    await _ensureOpen();
    await _file!.setPosition(offset);
    return await _file!.read(length);
  }

  @override
  Future<void> close() async {
    await _file?.close();
    _file = null;
  }
}

/// In-memory implementation of [RandomAccessSource] for fast I/O.
/// Loads data into memory once and serves all reads from memory.
class MemoryRandomAccessSource implements RandomAccessSource {
  final Uint8List _data;

  /// Creates a [MemoryRandomAccessSource] from the given [data].
  MemoryRandomAccessSource(this._data);

  @override
  Future<int> get length async => _data.length;

  @override
  Future<void> open() async {}

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset >= _data.length) return Uint8List(0);
    final end =
        (offset + length > _data.length) ? _data.length : offset + length;
    return _data.sublist(offset, end);
  }

  @override
  Future<void> close() async {}
}
