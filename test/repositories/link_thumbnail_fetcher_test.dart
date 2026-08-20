import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:stickerbox/repositories/link_thumbnail_fetcher.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(http.Request('GET', Uri.parse('https://example.com')));
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

    test('accepts TikTok short-link domains', () {
      expect(fetcher.isSupportedUrl('https://vm.tiktok.com/ZMabcdefg/'), isTrue);
      expect(fetcher.isSupportedUrl('https://vt.tiktok.com/ZSabcdefg/'), isTrue);
      expect(fetcher.isSupportedUrl('https://m.tiktok.com/v/1234567890.html'), isTrue);
    });

    test('rejects other hosts', () {
      expect(fetcher.isSupportedUrl('https://example.com/foo'), isFalse);
      expect(fetcher.isSupportedUrl('not a url'), isFalse);
    });
  });

  group('fetchThumbnailUrls', () {
    test('extracts the og:image content from the fetched page', () async {
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head><meta property="og:image" content="https://example.com/thumb.jpg"></head></html>',
          200,
        ),
      );

      final thumbnails = await fetcher.fetchThumbnailUrls('https://www.instagram.com/p/abc');

      expect(thumbnails, ['https://example.com/thumb.jpg']);
    });

    test('extracts every og:image tag from a carousel post', () async {
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head>'
          '<meta property="og:image" content="https://example.com/a.jpg">'
          '<meta property="og:image" content="https://example.com/b.jpg">'
          '</head></html>',
          200,
        ),
      );

      final thumbnails = await fetcher.fetchThumbnailUrls('https://www.instagram.com/p/abc');

      expect(thumbnails, ['https://example.com/a.jpg', 'https://example.com/b.jpg']);
    });

    test('falls back to the TikTok api-data JSON when there is no og:image tag', () async {
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head></head><body><script id="api-data" type="application/json">'
          '{"videoDetail":{"itemInfo":{"itemStruct":{"video":{"cover":"https://example.com/cover.jpg"}}}}}'
          '</script></body></html>',
          200,
        ),
      );

      final thumbnails = await fetcher.fetchThumbnailUrls('https://www.tiktok.com/@user/video/123');

      expect(thumbnails, ['https://example.com/cover.jpg']);
    });

    test('extracts every image from a TikTok photo-post carousel', () async {
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head></head><body><script id="api-data" type="application/json">'
          '{"videoDetail":{"itemInfo":{"itemStruct":{"imagePost":{"images":['
          '{"imageURL":{"urlList":["https://example.com/1.jpg"]}},'
          '{"imageURL":{"urlList":["https://example.com/2.jpg"]}}'
          ']}}}}}'
          '</script></body></html>',
          200,
        ),
      );

      final thumbnails = await fetcher.fetchThumbnailUrls('https://www.tiktok.com/@user/photo/123');

      expect(thumbnails, ['https://example.com/1.jpg', 'https://example.com/2.jpg']);
    });

    test('falls back to __UNIVERSAL_DATA_FOR_REHYDRATION__ for a TikTok photo post', () async {
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head></head><body>'
          '<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">'
          '{"__DEFAULT_SCOPE__":{"webapp.reflow.video.detail":{"itemInfo":{"itemStruct":'
          '{"imagePost":{"images":['
          '{"imageURL":{"urlList":["https://example.com/1.jpg"]}},'
          '{"imageURL":{"urlList":["https://example.com/2.jpg"]}}'
          ']}}}}}}'
          '</script></body></html>',
          200,
        ),
      );

      final thumbnails = await fetcher.fetchThumbnailUrls('https://www.tiktok.com/@user/photo/123');

      expect(thumbnails, ['https://example.com/1.jpg', 'https://example.com/2.jpg']);
    });

    test('resolves a TikTok short link before fetching, instead of following redirects inline', () async {
      when(() => client.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          const Stream.empty(),
          302,
          headers: {'location': 'https://www.tiktok.com/@user/photo/123'},
        ),
      );
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head></head><body><script id="api-data" type="application/json">'
          '{"videoDetail":{"itemInfo":{"itemStruct":{"video":{"cover":"https://example.com/cover.jpg"}}}}}'
          '</script></body></html>',
          200,
        ),
      );

      final thumbnails = await fetcher.fetchThumbnailUrls('https://vt.tiktok.com/ZSabcdefg/');

      expect(thumbnails, ['https://example.com/cover.jpg']);
      final captured = verify(() => client.get(captureAny(), headers: any(named: 'headers'))).captured;
      expect(captured.single, Uri.parse('https://www.tiktok.com/@user/photo/123'));
    });

    test('throws when the page has no og:image tag and no TikTok data', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('<html></html>', 200));

      expect(
        () => fetcher.fetchThumbnailUrls('https://www.instagram.com/p/abc'),
        throwsA(isA<LinkThumbnailException>()),
      );
    });

    test('throws on a non-200 response', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('', 404));

      expect(
        () => fetcher.fetchThumbnailUrls('https://www.instagram.com/p/abc'),
        throwsA(isA<LinkThumbnailException>()),
      );
    });

    test('throws for an unsupported host without making a request', () async {
      expect(
        () => fetcher.fetchThumbnailUrls('https://example.com/foo'),
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
