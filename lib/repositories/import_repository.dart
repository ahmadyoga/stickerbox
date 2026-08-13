import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Returns the first shared item whose text looks like an http(s) URL, or
/// null if none does. Pulled out as a top-level function so it's testable
/// without touching the `receive_sharing_intent` platform channel.
String? firstSupportedUrl(List<SharedMediaFile> shares) {
  for (final share in shares) {
    final uri = Uri.tryParse(share.path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return share.path;
    }
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
        .map(firstSupportedUrl)
        .where((url) => url != null)
        .cast<String>();
  }

  Future<String?> getInitialSharedUrl() async {
    final shares = await ReceiveSharingIntent.instance.getInitialMedia();
    final url = firstSupportedUrl(shares);
    await ReceiveSharingIntent.instance.reset();
    return url;
  }
}
