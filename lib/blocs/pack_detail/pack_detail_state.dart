import 'package:equatable/equatable.dart';

import '../../models/sticker_pack.dart';

enum PackDetailStatus { loading, notFound, loaded }

class PackDetailState extends Equatable {
  const PackDetailState({
    this.status = PackDetailStatus.loading,
    this.pack,
    this.canAddToWhatsApp = false,
  });

  final PackDetailStatus status;
  final StickerPack? pack;
  final bool canAddToWhatsApp;

  @override
  List<Object?> get props => [status, pack, canAddToWhatsApp];
}
