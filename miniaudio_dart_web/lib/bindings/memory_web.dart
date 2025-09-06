@JS('Module')
library miniaudio_memory;

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:js_interop_utils/js_interop_utils.dart';

// HEAP views
@JS('HEAPU8')
external JSUint8Array HEAPU8;
@JS('HEAPF32')
external JSFloat32Array HEAPF32;

// malloc/free
@JS('_malloc')
external JSNumber _malloc(JSNumber size);
@JS('_free')
external void _free(JSNumber ptr);

// Helpers
int allocate(int byteLength) => _malloc(byteLength.toJS).toDartInt;
void free(int ptr) => _free(ptr.toJS);

// Copy raw bytes (works for any encoded audio buffer)
void copyBytes(int destPtr, ByteBuffer buffer) {
  final src = buffer.asUint8List();
  final heap = HEAPU8.toDart;
  heap.setRange(destPtr, destPtr + src.length, src);
}

// Read back f32 samples
Float32List readF32(int ptr, int count) {
  assert((ptr & 3) == 0, 'readF32: pointer not 4-byte aligned'); // FIX: guard
  final view = HEAPF32.toDart;
  return Float32List.fromList(view.sublist(ptr >> 2, (ptr >> 2) + count));
}
