import 'package:flutter/services.dart';

import '../models/sticker_pack.dart';

class WhatsAppHandoff {
  WhatsAppHandoff({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('stickerbox/whatsapp');

  final MethodChannel _channel;

  Future<bool> isWhatsAppInstalled() async {
    final result = await _channel.invokeMethod<bool>('isWhatsAppInstalled');
    return result ?? false;
  }

  /// Sends [pack] to the native side, which serves it to WhatsApp (Android
  /// ContentProvider + intent, iOS pasteboard + URL scheme) and triggers the
  /// "Add to WhatsApp" UI.
  Future<void> addPack(StickerPack pack) async {
    await _channel.invokeMethod<void>('addPack', {
      'id': pack.id,
      'name': pack.name,
      'publisher': pack.publisherName,
      'trayIconPath': pack.trayIconPath,
      'stickers': [
        for (final sticker in pack.stickers)
          {'id': sticker.id, 'filePath': sticker.filePath, 'type': sticker.type.name},
      ],
    });
  }
}
