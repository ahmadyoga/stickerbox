import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sticker_creator/blocs/pack_detail/pack_detail_bloc.dart';
import 'package:sticker_creator/blocs/pack_detail/pack_detail_event.dart';
import 'package:sticker_creator/blocs/pack_detail/pack_detail_state.dart';
import 'package:sticker_creator/models/sticker.dart';
import 'package:sticker_creator/models/sticker_pack.dart';
import 'package:sticker_creator/repositories/pack_repository.dart';
import 'package:sticker_creator/repositories/sticker_processor.dart';

class MockPackRepository extends Mock implements PackRepository {}

class MockStickerProcessor extends Mock implements StickerProcessor {}

class _FakeStickerPack extends Fake implements StickerPack {}

/// Fakes getApplicationDocumentsDirectory() so the bloc can run under plain
/// flutter_test without a real platform channel (see test/blocs/import_bloc_test.dart
/// for the same pattern).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);

  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

StickerPack _packWith(int stickerCount, {String? trayIconPath}) => StickerPack(
      id: 'p1',
      name: 'Pack',
      publisherName: 'Me',
      trayIconPath: trayIconPath,
      stickers: [
        for (var i = 0; i < stickerCount; i++)
          Sticker(id: 's$i', filePath: '/tmp/s$i.webp', type: StickerType.static_),
      ],
    );

void main() {
  late MockPackRepository repository;
  late MockStickerProcessor processor;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(_FakeStickerPack());
  });

  setUp(() {
    repository = MockPackRepository();
    processor = MockStickerProcessor();
    tempDir = Directory.systemTemp.createTempSync('pack_detail_bloc_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  PackDetailBloc buildBloc() => PackDetailBloc(repository: repository, stickerProcessor: processor);

  blocTest<PackDetailBloc, PackDetailState>(
    'canAddToWhatsApp is false with fewer than 3 stickers',
    setUp: () => when(() => repository.getPack('p1')).thenReturn(_packWith(2, trayIconPath: '/tmp/tray.png')),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('p1')),
    expect: () => [
      isA<PackDetailState>()
          .having((s) => s.status, 'status', PackDetailStatus.loaded)
          .having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isFalse),
    ],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'canAddToWhatsApp is true with 3-30 stickers and a tray icon',
    setUp: () => when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png')),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('p1')),
    expect: () => [
      isA<PackDetailState>()
          .having((s) => s.status, 'status', PackDetailStatus.loaded)
          .having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isTrue),
    ],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'canAddToWhatsApp is false without a tray icon even at 3 stickers',
    setUp: () => when(() => repository.getPack('p1')).thenReturn(_packWith(3)),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('p1')),
    expect: () => [
      isA<PackDetailState>()
          .having((s) => s.status, 'status', PackDetailStatus.loaded)
          .having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isFalse),
    ],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'PackDetailLoadRequested emits notFound status for a missing pack',
    setUp: () => when(() => repository.getPack('missing')).thenReturn(null),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('missing')),
    expect: () => [const PackDetailState(status: PackDetailStatus.notFound)],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'StickerRemoved removes the sticker and re-saves the pack',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png'));
      when(() => repository.savePack(any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailState(
      status: PackDetailStatus.loaded,
      pack: _packWith(3, trayIconPath: '/tmp/tray.png'),
      canAddToWhatsApp: true,
    ),
    act: (bloc) => bloc.add(const StickerRemoved('s0')),
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      final saved = captured.single as StickerPack;
      expect(saved.stickers.any((s) => s.id == 's0'), isFalse);
    },
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'StickerRemoved no-ops instead of resurrecting a pack the repository can no longer find',
    setUp: () => when(() => repository.getPack('p1')).thenReturn(null),
    build: buildBloc,
    seed: () => PackDetailState(
      status: PackDetailStatus.loaded,
      pack: _packWith(3, trayIconPath: '/tmp/tray.png'),
      canAddToWhatsApp: true,
    ),
    act: (bloc) => bloc.add(const StickerRemoved('s0')),
    expect: () => [],
    verify: (_) => verifyNever(() => repository.savePack(any())),
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'StickersAdded appends processed stickers, re-saves the pack, and recomputes canAddToWhatsApp',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(2, trayIconPath: '/tmp/tray.png'));
      when(() => repository.savePack(any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailState(
      status: PackDetailStatus.loaded,
      pack: _packWith(2, trayIconPath: '/tmp/tray.png'),
    ),
    act: (bloc) => bloc.add(
      const StickersAdded(['/tmp/new1.webp', '/tmp/new2.webp'], StickerType.static_),
    ),
    expect: () => [
      isA<PackDetailState>()
          .having((s) => s.status, 'status', PackDetailStatus.loaded)
          .having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isTrue),
    ],
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      final saved = captured.single as StickerPack;
      expect(saved.stickers.length, 4);
      expect(saved.stickers.map((s) => s.filePath), containsAll(['/tmp/new1.webp', '/tmp/new2.webp']));
      expect(saved.stickers.where((s) => s.filePath == '/tmp/new1.webp').single.type, StickerType.static_);
    },
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'TrayIconSet encodes the cropped image via StickerProcessor, saves the tray path, and recomputes canAddToWhatsApp',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(3));
      when(() => repository.savePack(any())).thenAnswer((_) async {});
      when(() => processor.encodeTrayIcon(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailState(status: PackDetailStatus.loaded, pack: _packWith(3)),
    act: (bloc) => bloc.add(const TrayIconSet('/tmp/cropped.png')),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      isA<PackDetailState>()
          .having((s) => s.status, 'status', PackDetailStatus.loaded)
          .having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isTrue),
    ],
    verify: (_) {
      verify(() => processor.encodeTrayIcon('/tmp/cropped.png', any())).called(1);
      final captured = verify(() => repository.savePack(captureAny())).captured;
      final saved = captured.single as StickerPack;
      expect(saved.trayIconPath, isNotNull);
    },
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'PackRenameRequested renames and re-saves the pack',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png'));
      when(() => repository.savePack(any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailState(
      status: PackDetailStatus.loaded,
      pack: _packWith(3, trayIconPath: '/tmp/tray.png'),
      canAddToWhatsApp: true,
    ),
    act: (bloc) => bloc.add(const PackRenameRequested('New Name')),
    expect: () => [
      isA<PackDetailState>().having((s) => s.pack?.name, 'pack.name', 'New Name'),
    ],
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      expect((captured.single as StickerPack).name, 'New Name');
    },
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'PackDeleteRequested deletes the pack and emits notFound status',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png'));
      when(() => repository.deletePack('p1')).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailState(
      status: PackDetailStatus.loaded,
      pack: _packWith(3, trayIconPath: '/tmp/tray.png'),
      canAddToWhatsApp: true,
    ),
    act: (bloc) => bloc.add(const PackDeleteRequested()),
    expect: () => [const PackDetailState(status: PackDetailStatus.notFound)],
    verify: (_) => verify(() => repository.deletePack('p1')).called(1),
  );
}
