import 'package:equatable/equatable.dart';

import '../../models/sticker.dart';

sealed class ImportState extends Equatable {
  const ImportState();

  @override
  List<Object?> get props => [];
}

class ImportInitial extends ImportState {
  const ImportInitial();
}

class ImportProcessing extends ImportState {
  const ImportProcessing({this.current, this.total});

  final int? current;
  final int? total;

  @override
  List<Object?> get props => [current, total];
}

class ImportThumbnailPreview extends ImportState {
  const ImportThumbnailPreview(this.localPreviewPath);

  final String localPreviewPath;

  @override
  List<Object?> get props => [localPreviewPath];
}

class ImportReady extends ImportState {
  const ImportReady(this.processedFilePaths, this.type);

  final List<String> processedFilePaths;
  final StickerType type;

  @override
  List<Object?> get props => [processedFilePaths, type];
}

class ImportFailure extends ImportState {
  const ImportFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
