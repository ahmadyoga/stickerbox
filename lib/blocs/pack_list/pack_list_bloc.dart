import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/sticker_pack.dart';
import '../../repositories/pack_repository.dart';
import 'pack_list_event.dart';
import 'pack_list_state.dart';

class PackListBloc extends Bloc<PackListEvent, PackListState> {
  PackListBloc(this._repository) : super(const PackListState()) {
    on<PackListLoadRequested>(_onLoad);
    on<PackCreated>(_onCreated);
    on<PackRenamed>(_onRenamed);
    on<PackDeleted>(_onDeleted);
  }

  final PackRepository _repository;
  String? _lastCreatedPackId;

  String? get lastCreatedPackId => _lastCreatedPackId;

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

  void _emitLoaded(Emitter<PackListState> emit) {
    emit(PackListState(status: PackListStatus.loaded, packs: _repository.getAllPacks()));
  }

  Future<void> _onLoad(PackListLoadRequested event, Emitter<PackListState> emit) async {
    _emitLoaded(emit);
  }

  Future<void> _onCreated(PackCreated event, Emitter<PackListState> emit) async {
    final packId = _newId();
    _lastCreatedPackId = packId;
    await _repository.savePack(
      StickerPack(id: packId, name: event.name, publisherName: event.publisherName),
    );
    _emitLoaded(emit);
  }

  Future<void> _onRenamed(PackRenamed event, Emitter<PackListState> emit) async {
    final pack = _repository.getPack(event.id);
    if (pack == null) return;
    pack.name = event.newName;
    await _repository.savePack(pack);
    _emitLoaded(emit);
  }

  Future<void> _onDeleted(PackDeleted event, Emitter<PackListState> emit) async {
    await _repository.deletePack(event.id);
    _emitLoaded(emit);
  }
}
