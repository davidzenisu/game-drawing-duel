import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Whether [downloadFile] works here: on the web, it does.
const canDownload = true;

/// Hands [bytes] to the browser as a download named [name].
Future<void> downloadFile(Uint8List bytes, {required String name, required String mimeType}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(link);
  link.click();
  link.remove();
  // After the browser picked the file up.
  Future<void>.delayed(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
}
