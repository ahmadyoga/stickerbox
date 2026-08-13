import 'dart:io';

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

  static const _supportedHosts = ['tiktok.com', 'instagram.com', 'pinterest.com', 'pin.it'];

  bool isSupportedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    return _supportedHosts.any((h) => host == h || host.endsWith('.$h'));
  }

  /// Fetches the page at [url] and returns its og:image thumbnail URL.
  Future<String> fetchThumbnailUrl(String url) async {
    if (!isSupportedUrl(url)) {
      throw LinkThumbnailException(
        'Unsupported link: only TikTok, Instagram, and Pinterest links are supported',
      );
    }
    final response = await _client.get(
      Uri.parse(url),
      headers: {'User-Agent': 'Mozilla/5.0 (compatible; StickerCreator/1.0)'},
    );
    if (response.statusCode != 200) {
      throw LinkThumbnailException('Could not load link (HTTP ${response.statusCode})');
    }
    final document = html_parser.parse(response.body);
    final content = document.querySelector('meta[property="og:image"]')?.attributes['content'];
    if (content == null || content.isEmpty) {
      throw LinkThumbnailException('No preview image found for this link');
    }
    return content;
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
