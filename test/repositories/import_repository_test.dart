import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:stickerbox/repositories/import_repository.dart';

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  late MockImagePicker imagePicker;
  late ImportRepository repository;

  setUp(() {
    imagePicker = MockImagePicker();
    repository = ImportRepository(imagePicker: imagePicker);
  });

  test('pickStaticImages returns the picked file paths', () async {
    when(() => imagePicker.pickMultiImage()).thenAnswer(
      (_) async => [XFile('/tmp/a.jpg'), XFile('/tmp/b.jpg')],
    );

    final paths = await repository.pickStaticImages();

    expect(paths, ['/tmp/a.jpg', '/tmp/b.jpg']);
  });

  test('pickStaticImages returns an empty list when nothing picked', () async {
    when(() => imagePicker.pickMultiImage()).thenAnswer((_) async => []);

    final paths = await repository.pickStaticImages();

    expect(paths, isEmpty);
  });
}
