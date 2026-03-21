## 0.1.2

- Added `RandomAccessSource` abstraction to support non-file sources (like Android SAF).
- Added `openSource(RandomAccessSource source)` to `DictzipReader`.

## 0.1.1

- Added `readBulk` and `readBulkBytes` for efficient simultaneous reading of multiple ranges.
- Optimized performance by minimizing redundant decompressions.
- Added example and benchmark for bulk reading.

## 0.1.0

- Initial version.
- DictzipReader for random access to .dict.dz files.
