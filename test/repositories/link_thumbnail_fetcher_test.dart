import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sticker_creator/repositories/link_thumbnail_fetcher.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  late MockClient client;
  late LinkThumbnailFetcher fetcher;

  setUp(() {
    client = MockClient();
    fetcher = LinkThumbnailFetcher(client: client);
  });

  group('isSupportedUrl', () {
    test('accepts TikTok, Instagram, Pinterest hosts', () {
      expect(fetcher.isSupportedUrl('https://www.tiktok.com/@user/video/123'), isTrue);
      expect(fetcher.isSupportedUrl('https://instagram.com/p/abc'), isTrue);
      expect(fetcher.isSupportedUrl('https://pin.it/abc'), isTrue);
    });

    test('rejects other hosts', () {
      expect(fetcher.isSupportedUrl('https://example.com/foo'), isFalse);
      expect(fetcher.isSupportedUrl('not a url'), isFalse);
    });
  });

  group('fetchThumbnailUrl', () {
    test('extracts the og:image content from the fetched page', () async {
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head><meta property="og:image" content="https://example.com/thumb.jpg"></head></html>',
          200,
        ),
      );

      final thumbnail = await fetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc');

      expect(thumbnail, 'https://example.com/thumb.jpg');
    });

    test('throws when the page has no og:image tag', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('<html></html>', 200));

      expect(
        () => fetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc'),
        throwsA(isA<LinkThumbnailException>()),
      );
    });

    test('throws on a non-200 response', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('', 404));

      expect(
        () => fetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc'),
        throwsA(isA<LinkThumbnailException>()),
      );
    });

    test('throws for an unsupported host without making a request', () async {
      expect(
        () => fetcher.fetchThumbnailUrl('https://example.com/foo'),
        throwsA(isA<LinkThumbnailException>()),
      );
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    });
  });

  group('downloadImage', () {
    test('downloads and writes the image file successfully', () async {
      final testBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response.bytes(testBytes, 200),
      );

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/test_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      try {
        await fetcher.downloadImage('https://example.com/image.jpg', tempFile.path);

        expect(tempFile.existsSync(), isTrue);
        final writtenBytes = await tempFile.readAsBytes();
        expect(writtenBytes, testBytes);
      } finally {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      }
    });

    test('throws on a non-200 response', () async {
      when(() => client.get(any())).thenAnswer(
        (_) async => http.Response('', 404),
      );

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/test_image_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      expect(
        () => fetcher.downloadImage('https://example.com/image.jpg', tempFile.path),
        throwsA(isA<LinkThumbnailException>()),
      );
    });
  });
}
