import 'package:equatable/equatable.dart';

import '../../models/sticker_pack.dart';

sealed class PackListState extends Equatable {
  const PackListState();

  @override
  List<Object?> get props => [];
}

class PackListLoading extends PackListState {
  const PackListLoading();
}

class PackListLoaded extends PackListState {
  const PackListLoaded(this.packs);

  final List<StickerPack> packs;

  @override
  List<Object?> get props => [packs];
}
