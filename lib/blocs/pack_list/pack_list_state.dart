import 'package:equatable/equatable.dart';

import '../../models/sticker_pack.dart';

enum PackListStatus { loading, loaded }

class PackListState extends Equatable {
  const PackListState({this.status = PackListStatus.loading, this.packs = const []});

  final PackListStatus status;
  final List<StickerPack> packs;

  @override
  List<Object?> get props => [status, packs];
}
