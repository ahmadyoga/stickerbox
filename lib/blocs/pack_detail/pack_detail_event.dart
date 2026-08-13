import 'package:equatable/equatable.dart';

import '../../models/sticker.dart';

sealed class PackDetailEvent extends Equatable {
  const PackDetailEvent();

  @override
  List<Object?> get props => [];
}

class PackDetailLoadRequested extends PackDetailEvent {
  const PackDetailLoadRequested(this.packId);

  final String packId;

  @override
  List<Object?> get props => [packId];
}

class StickersAdded extends PackDetailEvent {
  const StickersAdded(this.processedFilePaths, this.type);

  final List<String> processedFilePaths;
  final StickerType type;

  @override
  List<Object?> get props => [processedFilePaths, type];
}

class StickerRemoved extends PackDetailEvent {
  const StickerRemoved(this.stickerId);

  final String stickerId;

  @override
  List<Object?> get props => [stickerId];
}

class TrayIconSet extends PackDetailEvent {
  const TrayIconSet(this.croppedImagePath);

  final String croppedImagePath;

  @override
  List<Object?> get props => [croppedImagePath];
}
