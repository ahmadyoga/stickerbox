import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:stickerbox/repositories/sticker_processor.dart';

void main() {
  test('encodeAnimatedGif produces an animated WebP file under 500KB', () async {
    final processor = StickerProcessor();
    final outputPath = p.join(
      Directory.systemTemp.path,
      'sticker_animated_test_${DateTime.now().microsecondsSinceEpoch}.webp',
    );

    await processor.encodeAnimatedGif('test/fixtures/sample.gif', outputPath);

    final output = File(outputPath);
    expect(output.existsSync(), isTrue);
    expect(output.lengthSync(), lessThanOrEqualTo(500 * 1024));

    // Decode the produced file back to confirm it's a genuine multi-frame
    // animated WebP, not just a static image of the right size.
    final decoded = img.decodeWebP(output.readAsBytesSync());
    expect(decoded, isNotNull);
    expect(decoded!.hasAnimation, isTrue);
    expect(decoded.frames.length, greaterThan(1));
    expect(decoded.width, equals(StickerProcessor.stickerDimension));
    expect(decoded.height, equals(StickerProcessor.stickerDimension));

    output.deleteSync();
  });
}
