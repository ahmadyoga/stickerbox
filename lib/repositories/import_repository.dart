import 'package:image_picker/image_picker.dart';

class ImportRepository {
  ImportRepository({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<List<String>> pickStaticImages() async {
    final files = await _imagePicker.pickMultiImage();
    return files.map((f) => f.path).toList();
  }

  Future<String?> pickGifFile() async {
    // ponytail: FilePicker.platform.pickFiles() doesn't exist in v11.0.3
    // Task 8 will add this properly with the correct API
    return null;
  }
}
