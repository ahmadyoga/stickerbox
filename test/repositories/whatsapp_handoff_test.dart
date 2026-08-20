import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickerbox/models/sticker_pack.dart';
import 'package:stickerbox/repositories/whatsapp_handoff.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('stickerbox/whatsapp');
  final log = <MethodCall>[];
  late WhatsAppHandoff handoff;

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'isWhatsAppInstalled':
          return true;
        case 'addPack':
          return null;
      }
      return null;
    });
    handoff = WhatsAppHandoff(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isWhatsAppInstalled forwards to the platform channel', () async {
    final result = await handoff.isWhatsAppInstalled();
    expect(result, isTrue);
    expect(log.single.method, 'isWhatsAppInstalled');
  });

  test('addPack sends pack id, name, publisher, and sticker file paths', () async {
    final pack = StickerPack(id: 'p1', name: 'My Pack', publisherName: 'Me', trayIconPath: '/tmp/tray.png');

    await handoff.addPack(pack);

    expect(log.single.method, 'addPack');
    final args = log.single.arguments as Map;
    expect(args['id'], 'p1');
    expect(args['name'], 'My Pack');
    expect(args['publisher'], 'Me');
    expect(args['trayIconPath'], '/tmp/tray.png');
  });
}
