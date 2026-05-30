import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readBytesFromPath(String path) async {
  return File(path).readAsBytes();
}

Future<void> deleteFileAtPath(String path) async {
  try {
    await File(path).delete();
  } catch (_) {}
}
