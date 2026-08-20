import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:stickerbox/blocs/import/import_bloc.dart';
import 'package:stickerbox/blocs/import/import_event.dart';
import 'package:stickerbox/blocs/import/import_state.dart';
import 'package:stickerbox/models/sticker.dart';
import 'package:stickerbox/repositories/import_repository.dart';
import 'package:stickerbox/repositories/link_thumbnail_fetcher.dart';
import 'package:stickerbox/repositories/sticker_processor.dart';

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
    'PickStaticImagesRequested reports current/total progress per image and emits a static ready state',
    setUp: () {
      when(() => importRepository.pickStaticImages())
          .thenAnswer((_) async => ['/tmp/a.jpg', '/tmp/b.jpg']);
      when(() => stickerProcessor.encodeStatic(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickStaticImagesRequested()),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportState(status: ImportStatus.processing),
      const ImportState(status: ImportStatus.processing, current: 1, total: 2),
      const ImportState(status: ImportStatus.processing, current: 2, total: 2),
      isA<ImportState>()
          .having((s) => s.status, 'status', ImportStatus.ready)
          .having((s) => s.processedFilePaths?.length, 'processedFilePaths.length', 2)
          .having((s) => s.type, 'type', StickerType.static_),
    ],
    verify: (_) {
      verify(() => importRepository.pickStaticImages()).called(1);
      verify(() => stickerProcessor.encodeStatic('/tmp/a.jpg', any())).called(1);
      verify(() => stickerProcessor.encodeStatic('/tmp/b.jpg', any())).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'PickGifRequested processes the picked GIF and emits an animated ready state with no progress fields',
    setUp: () {
      when(() => importRepository.pickGifFile()).thenAnswer((_) async => '/tmp/a.gif');
      when(() => stickerProcessor.encodeAnimatedGif(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickGifRequested()),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportState(status: ImportStatus.processing),
      isA<ImportState>()
          .having((s) => s.status, 'status', ImportStatus.ready)
          .having((s) => s.processedFilePaths?.length, 'processedFilePaths.length', 1)
          .having((s) => s.type, 'type', StickerType.animated),
    ],
    verify: (_) {
      verify(() => importRepository.pickGifFile()).called(1);
      verify(() => stickerProcessor.encodeAnimatedGif('/tmp/a.gif', any())).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'PickGifRequested returns to the initial state when the user cancels the picker',
    setUp: () {
      when(() => importRepository.pickGifFile()).thenAnswer((_) async => null);
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickGifRequested()),
    expect: () => [const ImportState(status: ImportStatus.processing), const ImportState()],
    verify: (_) {
      verifyNever(() => stickerProcessor.encodeAnimatedGif(any(), any()));
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted fetches and previews a thumbnail',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrls(any()),
      ).thenAnswer((_) async => ['https://example.com/thumb.jpg']);
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportState(status: ImportStatus.processing),
      isA<ImportState>()
          .having((s) => s.status, 'status', ImportStatus.thumbnailPreview)
          .having((s) => s.thumbnailPaths?.length, 'thumbnailPaths.length', 1),
    ],
    verify: (_) {
      verify(
        () => thumbnailFetcher.fetchThumbnailUrls('https://www.instagram.com/p/abc'),
      ).called(1);
      verify(
        () => thumbnailFetcher.downloadImage('https://example.com/thumb.jpg', any()),
      ).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted downloads every image found for a carousel post',
    setUp: () {
      when(() => thumbnailFetcher.fetchThumbnailUrls(any())).thenAnswer(
        (_) async => ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
      );
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportState(status: ImportStatus.processing),
      isA<ImportState>()
          .having((s) => s.status, 'status', ImportStatus.thumbnailPreview)
          .having((s) => s.thumbnailPaths?.length, 'thumbnailPaths.length', 2),
    ],
    verify: (_) {
      verify(() => thumbnailFetcher.downloadImage('https://example.com/a.jpg', any())).called(1);
      verify(() => thumbnailFetcher.downloadImage('https://example.com/b.jpg', any())).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted emits a failure state when the fetcher throws',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrls(any()),
      ).thenThrow(LinkThumbnailException('No preview image found for this link'));
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    expect: () => [
      const ImportState(status: ImportStatus.processing),
      const ImportState(status: ImportStatus.failure, failureMessage: 'No preview image found for this link'),
    ],
  );

  blocTest<ImportBloc, ImportState>(
    'LinkThumbnailConfirmed encodes every previewed thumbnail and emits a static ready state',
    setUp: () {
      when(() => thumbnailFetcher.fetchThumbnailUrls(any())).thenAnswer(
        (_) async => ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
      );
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
      when(() => stickerProcessor.encodeStatic(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) async {
      bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc'));
      final preview = await bloc.stream.firstWhere((s) => s.status == ImportStatus.thumbnailPreview);
      bloc.add(LinkThumbnailConfirmed(preview.thumbnailPaths!));
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportState(status: ImportStatus.processing),
      isA<ImportState>().having((s) => s.status, 'status', ImportStatus.thumbnailPreview),
      const ImportState(status: ImportStatus.processing),
      const ImportState(status: ImportStatus.processing, current: 1, total: 2),
      const ImportState(status: ImportStatus.processing, current: 2, total: 2),
      isA<ImportState>()
          .having((s) => s.status, 'status', ImportStatus.ready)
          .having((s) => s.processedFilePaths?.length, 'processedFilePaths.length', 2)
          .having((s) => s.type, 'type', StickerType.static_),
    ],
    verify: (_) {
      verify(() => stickerProcessor.encodeStatic(any(), any())).called(2);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkThumbnailConfirmed only encodes the caller-selected subset of a carousel',
    setUp: () {
      when(() => thumbnailFetcher.fetchThumbnailUrls(any())).thenAnswer(
        (_) async => ['https://example.com/a.jpg', 'https://example.com/b.jpg', 'https://example.com/c.jpg'],
      );
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
      when(() => stickerProcessor.encodeStatic(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) async {
      bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc'));
      final preview = await bloc.stream.firstWhere((s) => s.status == ImportStatus.thumbnailPreview);
      bloc.add(LinkThumbnailConfirmed([preview.thumbnailPaths![1]]));
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportState(status: ImportStatus.processing),
      isA<ImportState>().having((s) => s.status, 'status', ImportStatus.thumbnailPreview),
      const ImportState(status: ImportStatus.processing),
      const ImportState(status: ImportStatus.processing, current: 1, total: 1),
      isA<ImportState>()
          .having((s) => s.status, 'status', ImportStatus.ready)
          .having((s) => s.processedFilePaths?.length, 'processedFilePaths.length', 1),
    ],
    verify: (_) {
      verify(() => stickerProcessor.encodeStatic(any(), any())).called(1);
    },
  );
}
