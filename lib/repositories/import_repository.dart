import 'package:file_picker/file_picker.dart';
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
    );
    return result?.files.single.path;
  }
}
