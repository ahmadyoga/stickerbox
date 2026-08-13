import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sticker_creator/repositories/sticker_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encodeStatic produces a WebP file under 100KB', () async {
    final processor = StickerProcessor();
    final outputPath = p.join(
      Directory.systemTemp.path,
      'sticker_test_${DateTime.now().microsecondsSinceEpoch}.webp',
    );

    await processor.encodeStatic('test/fixtures/sample.jpg', outputPath);

    final output = File(outputPath);
    expect(output.existsSync(), isTrue);
    expect(output.lengthSync(), lessThanOrEqualTo(100 * 1024));

    output.deleteSync();
  });
}
