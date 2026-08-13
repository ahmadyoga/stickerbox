import 'dart:io';

import 'package:flutter/material.dart';

class StickerGridTile extends StatelessWidget {
  const StickerGridTile({super.key, required this.filePath, required this.onRemove});

  final String filePath;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.file(File(filePath), fit: BoxFit.cover)),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 16)),
          ),
        ),
      ],
    );
  }
}
