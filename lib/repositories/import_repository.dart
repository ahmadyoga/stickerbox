import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void _logShares(String source, List<SharedMediaFile> shares) {
  debugPrint('[ShareIntent] $source: ${shares.length} item(s)');
  for (final share in shares) {
    debugPrint('[ShareIntent]   type=${share.type} path=${share.path}');
  }
}

final _urlPattern = RegExp(r'https?://\S+');

/// Returns the first http(s) URL found in the shared items' text, or null if
/// none contains one. Apps like Pinterest share a caption plus the link
/// (e.g. "Take a look! 📌 https://pin.it/xyz"), not a bare URL, so this
/// scans for a URL substring rather than parsing the whole string as one.
/// Pulled out as a top-level function so it's testable without touching the
/// `receive_sharing_intent` platform channel.
String? firstSupportedUrl(List<SharedMediaFile> shares) {
  for (final share in shares) {
    final match = _urlPattern.firstMatch(share.path);
    if (match != null) return match.group(0);
  }
  return null;
}

class ImportRepository {
  ImportRepository({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<List<String>> pickStaticImages() async {
    final files = await _imagePicker.pickMultiImage();
    return files.map((f) => f.path).toList();
  }

  Future<String?> pickGifFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
    );
    return result?.files.single.path;
  }

  Stream<String> getSharedUrlStream() {
    return ReceiveSharingIntent.instance
        .getMediaStream()
        .map((shares) {
          _logShares('stream', shares);
          return firstSupportedUrl(shares);
        })
        .where((url) => url != null)
        .cast<String>();
  }

  Future<String?> getInitialSharedUrl() async {
    final shares = await ReceiveSharingIntent.instance.getInitialMedia();
    _logShares('initial', shares);
    final url = firstSupportedUrl(shares);
    await ReceiveSharingIntent.instance.reset();
    return url;
  }
}
