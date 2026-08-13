import 'dart:io';

import 'package:flutter/material.dart';

import '../models/sticker_pack.dart';

class PackListTile extends StatelessWidget {
  const PackListTile({super.key, required this.pack, required this.onTap, required this.onDelete});

  final StickerPack pack;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: pack.trayIconPath != null
          ? CircleAvatar(backgroundImage: FileImage(File(pack.trayIconPath!)))
          : const CircleAvatar(child: Icon(Icons.image_outlined)),
      title: Text(pack.name),
      subtitle: Text('${pack.stickers.length} stickers'),
      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      onTap: onTap,
    );
  }
}
