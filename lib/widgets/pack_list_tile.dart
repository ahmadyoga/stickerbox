import 'dart:io';

import 'package:flutter/material.dart';

import '../models/sticker_pack.dart';
import '../theme.dart';

class PackListTile extends StatelessWidget {
  const PackListTile({super.key, required this.pack, required this.onTap, required this.onMenu});

  final StickerPack pack;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final mini = pack.stickers.take(4).toList();
    final meta =
        '${pack.stickers.length} ${pack.stickers.length == 1 ? 'sticker' : 'stickers'}'
        '${pack.trayIconPath == null ? ' · no tray icon' : ''}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surf,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 76,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.surf2,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.stick, width: 3),
              ),
              child: pack.trayIconPath != null
                  ? Image.file(File(pack.trayIconPath!), fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        'no\ntray',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: colors.mut),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.tx),
                  ),
                  const SizedBox(height: 3),
                  Text(meta, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.mut)),
                  if (mini.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        for (final sticker in mini)
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 4),
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: colors.surf2,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Image.file(File(sticker.filePath), fit: BoxFit.cover),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.more_vert), onPressed: onMenu),
          ],
        ),
      ),
    );
  }
}
