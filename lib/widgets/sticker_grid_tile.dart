import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

class StickerGridTile extends StatelessWidget {
  const StickerGridTile({
    super.key,
    required this.filePath,
    required this.isAnimated,
    required this.onRemove,
  });

  final String filePath;
  final bool isAnimated;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.stick, width: 3),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: Image.file(File(filePath), fit: BoxFit.cover)),
          if (isAnimated)
            Positioned(
              left: 7,
              top: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xA8100D0A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'GIF',
                  style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          Positioned(
            right: 6,
            top: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(color: Color(0x99100D0A), shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
