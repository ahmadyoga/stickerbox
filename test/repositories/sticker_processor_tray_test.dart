import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sticker_creator/repositories/sticker_processor.dart';

void main() {
  test('encodeTrayIcon produces a 96x96 PNG', () async {
    final processor = StickerProcessor();
    final outputPath = p.join(
      Directory.systemTemp.path,
      'tray_test_${DateTime.now().microsecondsSinceEpoch}.png',
    );

    await processor.encodeTrayIcon('test/fixtures/sample.jpg', outputPath);

    final bytes = await File(outputPath).readAsBytes();
    final decoded = img.decodePng(bytes)!;
    expect(decoded.width, 96);
    expect(decoded.height, 96);

    File(outputPath).deleteSync();
  });
}
