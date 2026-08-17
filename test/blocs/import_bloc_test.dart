import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sticker_creator/blocs/import/import_bloc.dart';
import 'package:sticker_creator/blocs/import/import_event.dart';
import 'package:sticker_creator/blocs/import/import_state.dart';
import 'package:sticker_creator/models/sticker.dart';
import 'package:sticker_creator/repositories/import_repository.dart';
import 'package:sticker_creator/repositories/link_thumbnail_fetcher.dart';
import 'package:sticker_creator/repositories/sticker_processor.dart';

class MockImportRepository extends Mock implements ImportRepository {}

class MockStickerProcessor extends Mock implements StickerProcessor {}

class MockLinkThumbnailFetcher extends Mock implements LinkThumbnailFetcher {}

/// Fakes getApplicationDocumentsDirectory() so the bloc can run under plain
/// flutter_test without a real platform channel (see test/hive/hive_setup_test.dart
/// for the same pattern).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);

  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late MockImportRepository importRepository;
  late MockStickerProcessor stickerProcessor;
  late MockLinkThumbnailFetcher thumbnailFetcher;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    importRepository = MockImportRepository();
    stickerProcessor = MockStickerProcessor();
    thumbnailFetcher = MockLinkThumbnailFetcher();
    tempDir = Directory.systemTemp.createTempSync('import_bloc_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ImportBloc buildBloc() => ImportBloc(
    importRepository: importRepository,
    stickerProcessor: stickerProcessor,
    thumbnailFetcher: thumbnailFetcher,
  );

  blocTest<ImportBloc, ImportState>(
    'PickStaticImagesRequested reports current/total progress per image and emits a static ImportReady',
    setUp: () {
      when(() => importRepository.pickStaticImages())
          .thenAnswer((_) async => ['/tmp/a.jpg', '/tmp/b.jpg']);
      when(() => stickerProcessor.encodeStatic(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickStaticImagesRequested()),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportProcessing(),
      const ImportProcessing(current: 1, total: 2),
      const ImportProcessing(current: 2, total: 2),
      isA<ImportReady>()
          .having((s) => s.processedFilePaths.length, 'processedFilePaths.length', 2)
          .having((s) => s.type, 'type', StickerType.static_),
    ],
    verify: (_) {
      verify(() => importRepository.pickStaticImages()).called(1);
      verify(() => stickerProcessor.encodeStatic('/tmp/a.jpg', any())).called(1);
      verify(() => stickerProcessor.encodeStatic('/tmp/b.jpg', any())).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'PickGifRequested processes the picked GIF and emits an animated ImportReady with no progress fields',
    setUp: () {
      when(() => importRepository.pickGifFile()).thenAnswer((_) async => '/tmp/a.gif');
      when(() => stickerProcessor.encodeAnimatedGif(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickGifRequested()),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportProcessing(),
      isA<ImportReady>()
          .having((s) => s.processedFilePaths.length, 'processedFilePaths.length', 1)
          .having((s) => s.type, 'type', StickerType.animated),
    ],
    verify: (_) {
      verify(() => importRepository.pickGifFile()).called(1);
      verify(() => stickerProcessor.encodeAnimatedGif('/tmp/a.gif', any())).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'PickGifRequested returns to ImportInitial when the user cancels the picker',
    setUp: () {
      when(() => importRepository.pickGifFile()).thenAnswer((_) async => null);
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickGifRequested()),
    expect: () => [const ImportProcessing(), const ImportInitial()],
    verify: (_) {
      verifyNever(() => stickerProcessor.encodeAnimatedGif(any(), any()));
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted fetches and previews a thumbnail',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrl(any()),
      ).thenAnswer((_) async => 'https://example.com/thumb.jpg');
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    wait: const Duration(milliseconds: 50),
    expect: () => [const ImportProcessing(), isA<ImportThumbnailPreview>()],
    verify: (_) {
      verify(
        () => thumbnailFetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc'),
      ).called(1);
      verify(
        () => thumbnailFetcher.downloadImage('https://example.com/thumb.jpg', any()),
      ).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted emits ImportFailure when the fetcher throws',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrl(any()),
      ).thenThrow(LinkThumbnailException('No preview image found for this link'));
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    expect: () => [const ImportProcessing(), const ImportFailure('No preview image found for this link')],
  );

  blocTest<ImportBloc, ImportState>(
    'LinkThumbnailConfirmed encodes the previewed thumbnail and emits a static ImportReady',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrl(any()),
      ).thenAnswer((_) async => 'https://example.com/thumb.jpg');
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
      when(() => stickerProcessor.encodeStatic(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) async {
      bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc'));
      await bloc.stream.firstWhere((s) => s is ImportThumbnailPreview);
      bloc.add(const LinkThumbnailConfirmed());
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportProcessing(),
      isA<ImportThumbnailPreview>(),
      const ImportProcessing(),
      isA<ImportReady>().having((s) => s.type, 'type', StickerType.static_),
    ],
    verify: (_) {
      verify(() => stickerProcessor.encodeStatic(any(), any())).called(1);
    },
  );
}
