import 'package:hive/hive.dart';

import '../models/sticker_pack.dart';

class PackRepository {
  PackRepository(this._box);

  final Box<StickerPack> _box;

  List<StickerPack> getAllPacks() => _box.values.toList();

  StickerPack? getPack(String id) => _box.get(id);

  Future<void> savePack(StickerPack pack) => _box.put(pack.id, pack);

  Future<void> deletePack(String id) => _box.delete(id);
}
