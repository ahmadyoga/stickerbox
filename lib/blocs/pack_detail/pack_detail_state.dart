import 'package:equatable/equatable.dart';

import '../../models/sticker_pack.dart';

sealed class PackDetailState extends Equatable {
  const PackDetailState();

  @override
  List<Object?> get props => [];
}

class PackDetailLoading extends PackDetailState {
  const PackDetailLoading();
}

class PackDetailNotFound extends PackDetailState {
  const PackDetailNotFound();
}

class PackDetailLoaded extends PackDetailState {
  const PackDetailLoaded(this.pack, this.canAddToWhatsApp);

  final StickerPack pack;
  final bool canAddToWhatsApp;

  @override
  List<Object?> get props => [pack, canAddToWhatsApp];
}
