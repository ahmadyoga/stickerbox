import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sticker.dart';
import '../models/sticker_pack.dart';

const packsBoxName = 'packs';

Future<Box<StickerPack>> setUpHive() async {
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(StickerPackAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(StickerAdapter());
  }
  return Hive.openBox<StickerPack>(packsBoxName);
}
