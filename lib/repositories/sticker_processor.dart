import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import 'compression.dart';

class StickerProcessor {
  static const staticTargetBytes = 100 * 1024;
  static const stickerDimension = 512;
  static const animatedTargetBytes = 500 * 1024;
  static const maxAnimatedFrames = 24; // ~3s at 8fps, well under WhatsApp's cap
  static const trayDimension = 96;

  /// Resizes an image file into a 96x96 PNG tray icon.
  Future<void> encodeTrayIcon(String inputPath, String outputPath) async {
    final source = img.decodeImage(await File(inputPath).readAsBytes());
    if (source == null) {
      throw StickerTooLargeException('Could not decode tray icon image');
    }
    final resized = img.copyResize(source, width: trayDimension, height: trayDimension);
    await File(outputPath).writeAsBytes(img.encodePng(resized));
  }

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

  /// Encodes a GIF file into a WhatsApp-compliant animated WebP sticker,
  /// writing the result to [outputPath].
  Future<void> encodeAnimatedGif(String inputPath, String outputPath) async {
    final decoded = img.decodeGif(await File(inputPath).readAsBytes());
    if (decoded == null || decoded.frames.isEmpty) {
      throw StickerTooLargeException('Could not decode GIF');
    }
    final sourceFrames = decoded.frames;

    var attempt = const AnimatedEncodeAttempt(colorCount: 256, frameStep: 1);
    while (true) {
      final processedFrames = <img.Image>[];
      for (
        var i = 0;
        i < sourceFrames.length && processedFrames.length < maxAnimatedFrames;
        i += attempt.frameStep
      ) {
        var frame = img.copyResize(
          sourceFrames[i],
          width: stickerDimension,
          height: stickerDimension,
        );
        frame = img.quantize(frame, numberOfColors: attempt.colorCount);
        frame.frameDuration = sourceFrames[i].frameDuration;
        processedFrames.add(frame);
      }
      if (processedFrames.isEmpty) {
        throw StickerTooLargeException('GIF has no usable frames');
      }
      final bytes = _encodeAnimatedWebP(processedFrames);
      final next = nextAnimatedAttempt(
        current: attempt,
        currentSizeBytes: bytes.length,
        targetBytes: animatedTargetBytes,
      );
      if (next == null) {
        await File(outputPath).writeAsBytes(bytes);
        return;
      }
      attempt = next;
    }
  }

  /// Encodes [frames] (all the same size) as an animated WebP file.
  ///
  /// The installed `image` package's [img.WebPEncoder] only knows how to
  /// write a single lossless VP8L frame (`supportsAnimation` is `false`), so
  /// it can't be used directly for a multi-frame sticker. Each frame is
  /// instead lossless-encoded on its own via [img.WebPEncoder], and the
  /// resulting VP8L chunks are wrapped by hand in a standard animated-WebP
  /// RIFF container (VP8X + ANIM + one ANMF per frame), which is what
  /// WhatsApp (and `img.decodeWebP`) expect.
  Uint8List _encodeAnimatedWebP(List<img.Image> frames) {
    final width = frames.first.width;
    final height = frames.first.height;
    final encoder = img.WebPEncoder();

    final vp8x = <int>[
      0x02, // flags: animation bit set, everything else off
      ..._uint24le(0), // reserved
      ..._uint24le(width - 1),
      ..._uint24le(height - 1),
    ];

    final anim = <int>[
      0xff, 0xff, 0xff, 0xff, // background color (opaque white)
      ..._uint16le(0), // loop count: 0 = infinite
    ];

    final body = BytesBuilder()
      ..add(_riffChunk('VP8X', vp8x))
      ..add(_riffChunk('ANIM', anim));

    for (final frame in frames) {
      // Full single-frame WebP file: 'RIFF' + size(4) + 'WEBP' + VP8L chunk.
      final singleFrameWebP = encoder.encode(frame, singleFrame: true);
      final vp8lChunk = singleFrameWebP.sublist(12);
      final duration = frame.frameDuration > 0 ? frame.frameDuration : 100;
      final anmfPayload = <int>[
        ..._uint24le(0), // frame x offset
        ..._uint24le(0), // frame y offset
        ..._uint24le(frame.width - 1),
        ..._uint24le(frame.height - 1),
        ..._uint24le(duration), // duration in ms
        0x00, // reserved/blend/dispose flags
        ...vp8lChunk,
      ];
      body.add(_riffChunk('ANMF', anmfPayload));
    }

    final payload = body.toBytes();
    final out = BytesBuilder()
      ..add('RIFF'.codeUnits)
      ..add(_uint32le(4 + payload.length))
      ..add('WEBP'.codeUnits)
      ..add(payload);
    return out.toBytes();
  }

  List<int> _riffChunk(String tag, List<int> payload) => [
    ...tag.codeUnits,
    ..._uint32le(payload.length),
    ...payload,
    if (payload.length.isOdd) 0,
  ];

  List<int> _uint16le(int v) => [v & 0xff, (v >> 8) & 0xff];

  List<int> _uint24le(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff];

  List<int> _uint32le(int v) => [
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ];
}
