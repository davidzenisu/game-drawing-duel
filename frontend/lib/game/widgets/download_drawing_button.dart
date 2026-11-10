import 'package:flutter/material.dart';

import '../../platform/download.dart';
import '../rules/models.dart';
import 'sketch_canvas.dart';

/// App bar action saving [card]'s drawing as a PNG on its cardboard card,
/// named after the character. Only where the browser can download
/// ([canDownload]); hidden elsewhere.
class DownloadDrawingButton extends StatefulWidget {
  const DownloadDrawingButton({super.key, required this.card, this.available = canDownload});

  final CharacterCard card;

  /// Whether downloads work here; [canDownload] unless a test says otherwise.
  final bool available;

  /// E.g. "Kim - Baron of the Brunch Table.png", without characters file
  /// systems don't allow.
  static String fileName(CharacterCard card) {
    final name = '${card.subject} - ${card.title}'.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').trim();
    return '${name.isEmpty ? 'drawing' : name}.png';
  }

  @override
  State<DownloadDrawingButton> createState() => _DownloadDrawingButtonState();
}

class _DownloadDrawingButtonState extends State<DownloadDrawingButton> {
  bool _saving = false;

  Future<void> _download() async {
    setState(() => _saving = true);
    try {
      final png = await sketchPng(widget.card.sketch);
      await downloadFile(png, name: DownloadDrawingButton.fileName(widget.card), mimeType: 'image/png');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't download the drawing.")));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.available) return const SizedBox.shrink();
    return IconButton(
      onPressed: _saving ? null : _download,
      tooltip: 'Download drawing',
      icon: _saving
          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
          : const Icon(Icons.download_rounded),
    );
  }
}
