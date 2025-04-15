import 'dart:typed_data';

class ReadBufferResult {
  final Uint8List data;
  final int size;

  ReadBufferResult({required this.data, required this.size});
}