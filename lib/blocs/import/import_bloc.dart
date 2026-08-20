import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/sticker.dart';
import '../../repositories/import_repository.dart';
import '../../repositories/link_thumbnail_fetcher.dart';
import '../../repositories/sticker_processor.dart';
import 'import_event.dart';
import 'import_state.dart';

class ImportBloc extends Bloc<ImportEvent, ImportState> {
  ImportBloc({
    required this.importRepository,
    required this.stickerProcessor,
    required this.thumbnailFetcher,
  }) : super(const ImportState()) {
    on<PickStaticImagesRequested>(_onPickStaticImages);
    on<PickGifRequested>(_onPickGif);
    on<LinkUrlSubmitted>(_onLinkUrlSubmitted);
    on<LinkThumbnailConfirmed>(_onLinkThumbnailConfirmed);
  }

  final ImportRepository importRepository;
  final StickerProcessor stickerProcessor;
  final LinkThumbnailFetcher thumbnailFetcher;

  Future<String> _newOutputPath(String extension) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    return p.join(dir.path, 'stickers', '$id.$extension');
  }

  Future<void> _onPickStaticImages(
    PickStaticImagesRequested event,
    Emitter<ImportState> emit,
  ) async {
    emit(const ImportState(status: ImportStatus.processing));
    try {
      final picked = await importRepository.pickStaticImages();
      final total = picked.length;
      final outputs = <String>[];
      for (var i = 0; i < picked.length; i++) {
        final outputPath = await _newOutputPath('webp');
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await stickerProcessor.encodeStatic(picked[i], outputPath);
        outputs.add(outputPath);
        emit(ImportState(status: ImportStatus.processing, current: i + 1, total: total));
      }
      emit(ImportState(status: ImportStatus.ready, processedFilePaths: outputs, type: StickerType.static_));
    } catch (e) {
      emit(ImportState(status: ImportStatus.failure, failureMessage: e.toString()));
    }
  }

  Future<void> _onPickGif(PickGifRequested event, Emitter<ImportState> emit) async {
    emit(const ImportState(status: ImportStatus.processing));
    try {
      final inputPath = await importRepository.pickGifFile();
      if (inputPath == null) {
        emit(const ImportState());
        return;
      }
      final outputPath = await _newOutputPath('webp');
      await Directory(p.dirname(outputPath)).create(recursive: true);
      await stickerProcessor.encodeAnimatedGif(inputPath, outputPath);
      emit(
        ImportState(status: ImportStatus.ready, processedFilePaths: [outputPath], type: StickerType.animated),
      );
    } catch (e) {
      emit(ImportState(status: ImportStatus.failure, failureMessage: e.toString()));
    }
  }

  Future<void> _onLinkUrlSubmitted(LinkUrlSubmitted event, Emitter<ImportState> emit) async {
    emit(const ImportState(status: ImportStatus.processing));
    try {
      final thumbnailUrls = await thumbnailFetcher.fetchThumbnailUrls(event.url);
      final localPaths = <String>[];
      for (final thumbnailUrl in thumbnailUrls) {
        final localPath = await _newOutputPath('jpg');
        await Directory(p.dirname(localPath)).create(recursive: true);
        await thumbnailFetcher.downloadImage(thumbnailUrl, localPath);
        localPaths.add(localPath);
      }
      emit(ImportState(status: ImportStatus.thumbnailPreview, thumbnailPaths: localPaths));
    } on LinkThumbnailException catch (e) {
      emit(ImportState(status: ImportStatus.failure, failureMessage: e.message));
    } catch (e) {
      emit(ImportState(status: ImportStatus.failure, failureMessage: e.toString()));
    }
  }

  Future<void> _onLinkThumbnailConfirmed(
    LinkThumbnailConfirmed event,
    Emitter<ImportState> emit,
  ) async {
    final pending = event.selectedPaths;
    if (pending.isEmpty) return;
    emit(const ImportState(status: ImportStatus.processing));
    try {
      final total = pending.length;
      final outputs = <String>[];
      for (var i = 0; i < pending.length; i++) {
        final outputPath = await _newOutputPath('webp');
        await stickerProcessor.encodeStatic(pending[i], outputPath);
        outputs.add(outputPath);
        emit(ImportState(status: ImportStatus.processing, current: i + 1, total: total));
      }
      emit(ImportState(status: ImportStatus.ready, processedFilePaths: outputs, type: StickerType.static_));
    } catch (e) {
      emit(ImportState(status: ImportStatus.failure, failureMessage: e.toString()));
    }
  }
}
