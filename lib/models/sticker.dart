import 'package:hive/hive.dart';

enum StickerType { static_, animated }

class Sticker {
  Sticker({required this.id, required this.filePath, required this.type});

  final String id;
  final String filePath;
  final StickerType type;
}

class StickerAdapter extends TypeAdapter<Sticker> {
  @override
  final int typeId = 1;

  @override
  Sticker read(BinaryReader reader) {
    final id = reader.readString();
    final filePath = reader.readString();
    final type = StickerType.values[reader.readByte()];
    return Sticker(id: id, filePath: filePath, type: type);
  }

  @override
  void write(BinaryWriter writer, Sticker obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.filePath);
    writer.writeByte(obj.type.index);
  }
}
