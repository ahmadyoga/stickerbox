import 'package:equatable/equatable.dart';

import '../../models/sticker.dart';

enum ImportStatus { initial, processing, thumbnailPreview, ready, failure }

class ImportState extends Equatable {
  const ImportState({
    this.status = ImportStatus.initial,
    this.current,
    this.total,
    this.thumbnailPaths,
    this.processedFilePaths,
    this.type,
    this.failureMessage,
  });

  final ImportStatus status;
  final int? current;
  final int? total;
  final List<String>? thumbnailPaths;
  final List<String>? processedFilePaths;
  final StickerType? type;
  final String? failureMessage;

  @override
  List<Object?> get props => [
    status,
    current,
    total,
    thumbnailPaths,
    processedFilePaths,
    type,
    failureMessage,
  ];
}
