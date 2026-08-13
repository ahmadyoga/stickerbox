import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  }) : super(const ImportInitial()) {
    on<PickStaticImagesRequested>(_onPickStaticImages);
    on<PickGifRequested>(_onPickGif);
    on<LinkUrlSubmitted>(_onLinkUrlSubmitted);
    on<LinkThumbnailConfirmed>(_onLinkThumbnailConfirmed);
  }

  final ImportRepository importRepository;
  final StickerProcessor stickerProcessor;
  final LinkThumbnailFetcher thumbnailFetcher;

  String? _pendingThumbnailPath;

  Future<String> _newOutputPath(String extension) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    return p.join(dir.path, 'stickers', '$id.$extension');
  }

  Future<void> _onPickStaticImages(
    PickStaticImagesRequested event,
    Emitter<ImportState> emit,
  ) async {
    emit(const ImportProcessing());
    try {
      final picked = await importRepository.pickStaticImages();
      final outputs = <String>[];
      for (final inputPath in picked) {
        final outputPath = await _newOutputPath('webp');
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await stickerProcessor.encodeStatic(inputPath, outputPath);
        outputs.add(outputPath);
      }
      emit(ImportReady(outputs));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }

  Future<void> _onPickGif(PickGifRequested event, Emitter<ImportState> emit) async {
    emit(const ImportProcessing());
    try {
      final inputPath = await importRepository.pickGifFile();
      if (inputPath == null) {
        emit(const ImportInitial());
        return;
      }
      final outputPath = await _newOutputPath('webp');
      await Directory(p.dirname(outputPath)).create(recursive: true);
      await stickerProcessor.encodeAnimatedGif(inputPath, outputPath);
      emit(ImportReady([outputPath]));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }

  Future<void> _onLinkUrlSubmitted(LinkUrlSubmitted event, Emitter<ImportState> emit) async {
    emit(const ImportProcessing());
    try {
      final thumbnailUrl = await thumbnailFetcher.fetchThumbnailUrl(event.url);
      final localPath = await _newOutputPath('jpg');
      await Directory(p.dirname(localPath)).create(recursive: true);
      await thumbnailFetcher.downloadImage(thumbnailUrl, localPath);
      _pendingThumbnailPath = localPath;
      emit(ImportThumbnailPreview(localPath));
    } on LinkThumbnailException catch (e) {
      emit(ImportFailure(e.message));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }

  Future<void> _onLinkThumbnailConfirmed(
    LinkThumbnailConfirmed event,
    Emitter<ImportState> emit,
  ) async {
    final pending = _pendingThumbnailPath;
    if (pending == null) return;
    emit(const ImportProcessing());
    try {
      final outputPath = await _newOutputPath('webp');
      await stickerProcessor.encodeStatic(pending, outputPath);
      emit(ImportReady([outputPath]));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }
}
