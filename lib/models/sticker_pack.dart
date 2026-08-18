import 'package:hive/hive.dart';

import 'sticker.dart';

class StickerPack {
  StickerPack({
    required this.id,
    required this.name,
    required this.publisherName,
    this.trayIconPath,
    List<Sticker>? stickers,
  }) : stickers = stickers ?? [];

  final String id;
  String name;
  String publisherName;
  String? trayIconPath;
  final List<Sticker> stickers;

  /// Detached copy. Hive's non-lazy box hands back the same cached instance on
  /// every read, so mutating it in place would leave bloc states comparing
  /// equal (identity) to their pre-mutation snapshot and the emit gets dropped.
  StickerPack copy() => StickerPack(
        id: id,
        name: name,
        publisherName: publisherName,
        trayIconPath: trayIconPath,
        stickers: List.of(stickers),
      );
}

class StickerPackAdapter extends TypeAdapter<StickerPack> {
  @override
  final int typeId = 0;

  @override
  StickerPack read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final publisherName = reader.readString();
    final hasTrayIcon = reader.readBool();
    final trayIconPath = hasTrayIcon ? reader.readString() : null;
    final stickerCount = reader.readInt();
    final stickers = <Sticker>[
      for (var i = 0; i < stickerCount; i++) reader.read() as Sticker,
    ];
    return StickerPack(
      id: id,
      name: name,
      publisherName: publisherName,
      trayIconPath: trayIconPath,
      stickers: stickers,
    );
  }

  @override
  void write(BinaryWriter writer, StickerPack obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeString(obj.publisherName);
    writer.writeBool(obj.trayIconPath != null);
    if (obj.trayIconPath != null) writer.writeString(obj.trayIconPath!);
    writer.writeInt(obj.stickers.length);
    for (final sticker in obj.stickers) {
      writer.write(sticker);
    }
  }
}
