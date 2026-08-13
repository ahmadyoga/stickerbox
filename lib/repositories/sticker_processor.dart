import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'compression.dart';

class StickerProcessor {
  static const staticTargetBytes = 100 * 1024;
  static const stickerDimension = 512;

  /// Encodes a single image file into a WhatsApp-compliant static WebP
  /// sticker, writing the result to [outputPath].
  Future<void> encodeStatic(String inputPath, String outputPath) async {
    var quality = 90;
    while (true) {
      final bytes = await FlutterImageCompress.compressWithFile(
        inputPath,
        format: CompressFormat.webp,
        minWidth: stickerDimension,
        minHeight: stickerDimension,
        quality: quality,
      );
      if (bytes == null) {
        throw StickerTooLargeException('Failed to encode sticker image');
      }
      final next = nextStaticQuality(
        currentQuality: quality,
        currentSizeBytes: bytes.length,
        targetBytes: staticTargetBytes,
      );
      if (next == null) {
        await File(outputPath).writeAsBytes(bytes);
        return;
      }
      quality = next;
    }
  }
}
