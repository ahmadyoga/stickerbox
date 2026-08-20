import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class LinkThumbnailException implements Exception {
  LinkThumbnailException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LinkThumbnailFetcher {
  LinkThumbnailFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _supportedHosts = [
    'tiktok.com',
    'vm.tiktok.com',
    'vt.tiktok.com',
    'instagram.com',
    'pinterest.com',
    'pin.it',
  ];

  static const _shortLinkHosts = ['vm.tiktok.com', 'vt.tiktok.com'];

  static const _userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';

  bool isSupportedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    return _supportedHosts.any((h) => host == h || host.endsWith('.$h'));
  }

  /// Fetches the page at [url] and returns every image found for it — a
  /// single-image post returns a one-element list, a carousel/photo-post
  /// returns one per image.
  Future<List<String>> fetchThumbnailUrls(String url) async {
    if (!isSupportedUrl(url)) {
      throw LinkThumbnailException(
        'Unsupported link: only TikTok, Instagram, and Pinterest links are supported',
      );
    }
    final fetchUrl = await _resolveShortLink(url) ?? url;
    final response = await _client.get(
      Uri.parse(fetchUrl),
      // TikTok serves a stripped-down bot page (no data at all) to
      // non-browser User-Agents, so this has to look like a real one.
      headers: {'User-Agent': _userAgent},
    );
    debugPrint('[LinkFetch] GET $fetchUrl -> status=${response.statusCode} bodyLen=${response.body.length}');
    if (response.statusCode != 200) {
      throw LinkThumbnailException('Could not load link (HTTP ${response.statusCode})');
    }
    final images = _extractOgImages(response.body);
    debugPrint('[LinkFetch] og:image count=${images.length}');
    final content = images.isNotEmpty ? images : _extractTikTokImages(response.body);
    debugPrint(
      '[LinkFetch] hasApiData=${response.body.contains('id="api-data"')} '
      'hasRehydration=${response.body.contains('__UNIVERSAL_DATA_FOR_REHYDRATION__')} '
      'tiktokImageCount=${content.length}',
    );
    if (content.isEmpty) {
      throw LinkThumbnailException('No preview image found for this link');
    }
    return content;
  }

  /// TikTok's short-link hosts sometimes serve a stripped bot-detection page
  /// (no post data at all) when the redirect to the long-form URL is
  /// auto-followed within a single request. Resolving the redirect
  /// separately and fetching the long URL fresh reliably avoids that.
  Future<String?> _resolveShortLink(String url) async {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || !_shortLinkHosts.contains(host)) return null;
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['User-Agent'] = _userAgent;
      final streamed = await _client.send(request);
      final location = streamed.headers['location'];
      debugPrint('[LinkFetch] resolved short link $url -> $location');
      return location;
    } catch (e) {
      debugPrint('[LinkFetch] short link resolve failed: $e');
      return null;
    }
  }

  /// Carousel posts (Instagram, Pinterest) render one `og:image` tag per image.
  List<String> _extractOgImages(String body) {
    final document = html_parser.parse(body);
    return document
        .querySelectorAll('meta[property="og:image"]')
        .map((e) => e.attributes['content'])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList();
  }

  /// TikTok doesn't render og:image tags at all — the cover/photo URLs only
  /// exist embedded in a JSON blob. Video pages carry a dedicated `#api-data`
  /// script; photo posts don't get that tag and instead nest the same shape
  /// inside the `__UNIVERSAL_DATA_FOR_REHYDRATION__` blob's flat-keyed scope.
  List<String> _extractTikTokImages(String body) {
    final itemStruct = _apiDataItemStruct(body) ?? _rehydrationItemStruct(body);
    if (itemStruct == null) return const [];

    final images = itemStruct['imagePost']?['images'] as List<dynamic>?;
    if (images != null && images.isNotEmpty) {
      return images
          .map((img) => ((img as Map<String, dynamic>)['imageURL']?['urlList'] as List<dynamic>?)
              ?.firstOrNull as String?)
          .whereType<String>()
          .toList();
    }

    final video = itemStruct['video'] as Map<String, dynamic>?;
    final cover = video?['cover'] as String? ?? video?['originCover'] as String?;
    return cover != null ? [cover] : const [];
  }

  Map<String, dynamic>? _apiDataItemStruct(String body) {
    final match = RegExp(r'<script id="api-data"[^>]*>(.*?)</script>', dotAll: true).firstMatch(body);
    if (match == null) return null;
    try {
      final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      return data['videoDetail']?['itemInfo']?['itemStruct'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _rehydrationItemStruct(String body) {
    final match = RegExp(
      r'<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(body);
    if (match == null) return null;
    try {
      final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      final scope = data['__DEFAULT_SCOPE__'] as Map<String, dynamic>?;
      if (scope == null) return null;
      // The entry holding itemInfo.itemStruct shows up under different scope
      // keys across requests (observed both "webapp.reflow.video.detail" and
      // others for the same content), so scan every entry's shape instead of
      // trusting one fixed key name.
      for (final entry in scope.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        final itemStruct = value['itemInfo']?['itemStruct'] as Map<String, dynamic>?;
        if (itemStruct != null) {
          debugPrint('[LinkFetch] rehydration: found itemStruct under scope key "${entry.key}"');
          return itemStruct;
        }
      }
      debugPrint('[LinkFetch] rehydration: no itemStruct in any of ${scope.keys.length} scope keys');
      return null;
    } catch (e) {
      debugPrint('[LinkFetch] rehydration parse failed: $e');
      return null;
    }
  }

  /// Downloads the image at [imageUrl] and writes it to [outputPath].
  Future<void> downloadImage(String imageUrl, String outputPath) async {
    final response = await _client.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      throw LinkThumbnailException('Could not download preview image');
    }
    await File(outputPath).writeAsBytes(response.bodyBytes);
  }
}
