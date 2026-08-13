import 'package:equatable/equatable.dart';

sealed class ImportState extends Equatable {
  const ImportState();

  @override
  List<Object?> get props => [];
}

class ImportInitial extends ImportState {
  const ImportInitial();
}

class ImportProcessing extends ImportState {
  const ImportProcessing();
}

class ImportThumbnailPreview extends ImportState {
  const ImportThumbnailPreview(this.localPreviewPath);

  final String localPreviewPath;

  @override
  List<Object?> get props => [localPreviewPath];
}

class ImportReady extends ImportState {
  const ImportReady(this.processedFilePaths);

  final List<String> processedFilePaths;

  @override
  List<Object?> get props => [processedFilePaths];
}

class ImportFailure extends ImportState {
  const ImportFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
