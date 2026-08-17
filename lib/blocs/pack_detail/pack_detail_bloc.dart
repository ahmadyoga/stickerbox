import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/sticker.dart';
import '../../models/sticker_pack.dart';
import '../../repositories/pack_repository.dart';
import '../../repositories/sticker_processor.dart';
import 'pack_detail_event.dart';
import 'pack_detail_state.dart';

class PackDetailBloc extends Bloc<PackDetailEvent, PackDetailState> {
  PackDetailBloc({required this.repository, required this.stickerProcessor})
      : super(const PackDetailState()) {
    on<PackDetailLoadRequested>(_onLoad);
    on<StickersAdded>(_onStickersAdded);
    on<StickerRemoved>(_onStickerRemoved);
    on<TrayIconSet>(_onTrayIconSet);
    on<PackRenameRequested>(_onRenameRequested);
    on<PackDeleteRequested>(_onDeleteRequested);
  }

  final PackRepository repository;
  final StickerProcessor stickerProcessor;

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}';

  bool _canAdd(StickerPack pack) =>
      pack.stickers.length >= 3 && pack.stickers.length <= 30 && pack.trayIconPath != null;

  Future<void> _onLoad(PackDetailLoadRequested event, Emitter<PackDetailState> emit) async {
    final pack = repository.getPack(event.packId);
    if (pack == null) {
      emit(const PackDetailState(status: PackDetailStatus.notFound));
      return;
    }
    emit(PackDetailState(status: PackDetailStatus.loaded, pack: pack, canAddToWhatsApp: _canAdd(pack)));
  }

  /// Loads the currently-displayed pack fresh from the repository and applies
  /// [mutate] to it, then saves and re-emits. Reading `state` (rather than a
  /// separately-tracked id) means a mutation event works whether it follows a
  /// real `PackDetailLoadRequested` or a bloc_test `seed`.
  Future<void> _mutate(
    Emitter<PackDetailState> emit,
    void Function(StickerPack pack) mutate,
  ) async {
    final current = state;
    if (current.status != PackDetailStatus.loaded || current.pack == null) return;
    final pack = repository.getPack(current.pack!.id);
    if (pack == null) return;
    mutate(pack);
    await repository.savePack(pack);
    emit(PackDetailState(status: PackDetailStatus.loaded, pack: pack, canAddToWhatsApp: _canAdd(pack)));
  }

  Future<void> _onStickersAdded(StickersAdded event, Emitter<PackDetailState> emit) => _mutate(
    emit,
    (pack) => pack.stickers.addAll([
      for (final path in event.processedFilePaths)
        Sticker(id: _newId(), filePath: path, type: event.type),
    ]),
  );

  Future<void> _onStickerRemoved(StickerRemoved event, Emitter<PackDetailState> emit) => _mutate(
    emit,
    (pack) => pack.stickers.removeWhere((s) => s.id == event.stickerId),
  );

  Future<void> _onTrayIconSet(TrayIconSet event, Emitter<PackDetailState> emit) async {
    final current = state;
    if (current.status != PackDetailStatus.loaded || current.pack == null) return;
    final pack = repository.getPack(current.pack!.id);
    if (pack == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final trayIconPath = p.join(dir.path, 'stickers', '${_newId()}_tray.png');
    await Directory(p.dirname(trayIconPath)).create(recursive: true);
    await stickerProcessor.encodeTrayIcon(event.croppedImagePath, trayIconPath);
    pack.trayIconPath = trayIconPath;
    await repository.savePack(pack);
    emit(PackDetailState(status: PackDetailStatus.loaded, pack: pack, canAddToWhatsApp: _canAdd(pack)));
  }

  Future<void> _onRenameRequested(PackRenameRequested event, Emitter<PackDetailState> emit) =>
      _mutate(emit, (pack) => pack.name = event.newName);

  Future<void> _onDeleteRequested(PackDeleteRequested event, Emitter<PackDetailState> emit) async {
    final current = state;
    if (current.status != PackDetailStatus.loaded || current.pack == null) return;
    await repository.deletePack(current.pack!.id);
    emit(const PackDetailState(status: PackDetailStatus.notFound));
  }
}
