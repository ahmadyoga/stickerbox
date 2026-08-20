import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:stickerbox/repositories/import_repository.dart';

void main() {
  test('firstSupportedUrl returns the first text share that is a URL', () {
    final shares = [
      SharedMediaFile(path: 'just some text', type: SharedMediaType.text),
      SharedMediaFile(path: 'https://www.tiktok.com/@user/video/123', type: SharedMediaType.text),
    ];

    expect(firstSupportedUrl(shares), 'https://www.tiktok.com/@user/video/123');
  });

  test('firstSupportedUrl returns null when nothing looks like a URL', () {
    final shares = [SharedMediaFile(path: 'no links here', type: SharedMediaType.text)];

    expect(firstSupportedUrl(shares), isNull);
  });

  test('firstSupportedUrl extracts the URL from a caption Pinterest-style share', () {
    final shares = [
      SharedMediaFile(path: 'Take a look! 📌 https://pin.it/tGt2bo8wq', type: SharedMediaType.text),
    ];

    expect(firstSupportedUrl(shares), 'https://pin.it/tGt2bo8wq');
  });
}
