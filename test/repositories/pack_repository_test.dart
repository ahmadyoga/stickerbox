import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sticker_creator/models/sticker.dart';
import 'package:sticker_creator/models/sticker_pack.dart';
import 'package:sticker_creator/repositories/pack_repository.dart';

void main() {
  late Box<StickerPack> box;
  late PackRepository repository;

  setUp(() async {
    Hive.init('.dart_tool/test_hive');
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(StickerPackAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(StickerAdapter());
    box = await Hive.openBox<StickerPack>('test_packs_${DateTime.now().microsecondsSinceEpoch}');
    repository = PackRepository(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  test('savePack then getPack round-trips all fields including stickers', () async {
    final pack = StickerPack(
      id: 'pack-1',
      name: 'My Pack',
      publisherName: 'Me',
      trayIconPath: '/tmp/tray.png',
      stickers: [
        Sticker(id: 's1', filePath: '/tmp/s1.webp', type: StickerType.static_),
        Sticker(id: 's2', filePath: '/tmp/s2.webp', type: StickerType.animated),
      ],
    );

    await repository.savePack(pack);
    final loaded = repository.getPack('pack-1')!;

    expect(loaded.id, 'pack-1');
    expect(loaded.name, 'My Pack');
    expect(loaded.publisherName, 'Me');
    expect(loaded.trayIconPath, '/tmp/tray.png');
    expect(loaded.stickers, hasLength(2));
    expect(loaded.stickers[0].id, 's1');
    expect(loaded.stickers[0].type, StickerType.static_);
    expect(loaded.stickers[1].type, StickerType.animated);
  });

  test('getAllPacks returns every saved pack; deletePack removes one', () async {
    await repository.savePack(StickerPack(id: 'a', name: 'A', publisherName: 'Me'));
    await repository.savePack(StickerPack(id: 'b', name: 'B', publisherName: 'Me'));

    expect(repository.getAllPacks(), hasLength(2));

    await repository.deletePack('a');

    expect(repository.getAllPacks(), hasLength(1));
    expect(repository.getPack('a'), isNull);
  });
}
