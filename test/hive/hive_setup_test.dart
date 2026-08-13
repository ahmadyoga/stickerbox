import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sticker_creator/hive/hive_setup.dart';
import 'package:sticker_creator/models/sticker_pack.dart';

/// Fakes getApplicationDocumentsDirectory() so setUpHive() can run under
/// plain flutter_test without a real platform channel.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);

  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hive_setup_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    if (Hive.isBoxOpen(packsBoxName)) {
      await Hive.box<StickerPack>(packsBoxName).close();
    }
    await Hive.deleteBoxFromDisk(packsBoxName);
    tempDir.deleteSync(recursive: true);
  });

  test('setUpHive returns a working, correctly-named Box<StickerPack>', () async {
    final box = await setUpHive();

    expect(box.name, packsBoxName);
    expect(box.isOpen, isTrue);

    final pack = StickerPack(id: 'p1', name: 'Pack', publisherName: 'Me');
    await box.put(pack.id, pack);

    final loaded = box.get('p1')!;
    expect(loaded.name, 'Pack');
    expect(loaded.publisherName, 'Me');
  });
}
