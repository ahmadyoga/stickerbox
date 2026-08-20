import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:stickerbox/repositories/sticker_processor.dart';

// Exercises the real flutter_image_compress platform channel on-device.
// See test/repositories/sticker_processor_static_test.dart for why this
// can't run under plain `flutter test` (no native plugin registered there).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('encodeStatic produces a WebP file under 100KB', () async {
    // The fixture lives in the host repo at test/fixtures/sample.jpg; it's
    // bundled as a Flutter asset (see pubspec.yaml) so it's reachable from
    // the device under test, then copied to a real on-device file path.
    final fixtureBytes = await rootBundle.load('test/fixtures/sample.jpg');
    final inputPath = p.join(Directory.systemTemp.path, 'sample_input.jpg');
    await File(
      inputPath,
    ).writeAsBytes(fixtureBytes.buffer.asUint8List(), flush: true);

    final processor = StickerProcessor();
    final outputPath = p.join(
      Directory.systemTemp.path,
      'sticker_test_${DateTime.now().microsecondsSinceEpoch}.webp',
    );

    await processor.encodeStatic(inputPath, outputPath);

    final output = File(outputPath);
    expect(output.existsSync(), isTrue);
    expect(output.lengthSync(), lessThanOrEqualTo(100 * 1024));

    output.deleteSync();
    File(inputPath).deleteSync();
  });
}
