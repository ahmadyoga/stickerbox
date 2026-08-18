import 'package:hive/hive.dart';

import '../models/sticker_pack.dart';

class PackRepository {
  PackRepository(this._box);

  final Box<StickerPack> _box;

  // Copies, not the live Hive-cached instances: see StickerPack.copy().
  List<StickerPack> getAllPacks() => _box.values.map((p) => p.copy()).toList();

  StickerPack? getPack(String id) => _box.get(id)?.copy();

  Future<void> savePack(StickerPack pack) => _box.put(pack.id, pack);

  Future<void> deletePack(String id) => _box.delete(id);
}
