import 'dart:typed_data';

/// Whether [downloadFile] works here: only on the web.
const canDownload = false;

/// Not available outside the web.
Future<void> downloadFile(Uint8List bytes, {required String name, required String mimeType}) =>
    throw UnsupportedError('Downloads only work in the browser.');
