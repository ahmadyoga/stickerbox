import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sticker_creator/blocs/pack_list/pack_list_bloc.dart';
import 'package:sticker_creator/blocs/pack_list/pack_list_event.dart';
import 'package:sticker_creator/blocs/pack_list/pack_list_state.dart';
import 'package:sticker_creator/models/sticker_pack.dart';
import 'package:sticker_creator/repositories/pack_repository.dart';

class MockPackRepository extends Mock implements PackRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(StickerPack(id: 'x', name: 'x', publisherName: 'x'));
  });

  late MockPackRepository repository;

  setUp(() => repository = MockPackRepository());

  blocTest<PackListBloc, PackListState>(
    'PackListLoadRequested loads packs from the repository',
    setUp: () => when(() => repository.getAllPacks()).thenReturn(
      [StickerPack(id: '1', name: 'A', publisherName: 'Me')],
    ),
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackListLoadRequested()),
    expect: () => [
      isA<PackListState>().having((s) => s.status, 'status', PackListStatus.loaded),
    ],
  );

  blocTest<PackListBloc, PackListState>(
    'PackCreated saves a new pack then reloads',
    setUp: () {
      when(() => repository.savePack(any())).thenAnswer((_) async {});
      when(() => repository.getAllPacks()).thenReturn(
        [StickerPack(id: 'new', name: 'New Pack', publisherName: 'Me')],
      );
    },
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackCreated('New Pack', 'Me')),
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      final saved = captured.single as StickerPack;
      expect(saved.name, 'New Pack');
      expect(saved.publisherName, 'Me');
    },
  );

  blocTest<PackListBloc, PackListState>(
    'PackRenamed saves the renamed pack then reloads',
    setUp: () {
      when(() => repository.getPack('1')).thenReturn(
        StickerPack(id: '1', name: 'Old', publisherName: 'Me'),
      );
      when(() => repository.savePack(any())).thenAnswer((_) async {});
      when(() => repository.getAllPacks()).thenReturn(
        [StickerPack(id: '1', name: 'New Name', publisherName: 'Me')],
      );
    },
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackRenamed('1', 'New Name')),
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      final saved = captured.single as StickerPack;
      expect(saved.name, 'New Name');
    },
  );

  blocTest<PackListBloc, PackListState>(
    'PackRenamed is a no-op when the pack does not exist',
    setUp: () => when(() => repository.getPack('missing')).thenReturn(null),
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackRenamed('missing', 'New Name')),
    verify: (_) {
      verifyNever(() => repository.savePack(any()));
    },
  );

  blocTest<PackListBloc, PackListState>(
    'PackDeleted removes a pack then reloads',
    setUp: () {
      when(() => repository.deletePack('1')).thenAnswer((_) async {});
      when(() => repository.getAllPacks()).thenReturn([]);
    },
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackDeleted('1')),
    expect: () => [const PackListState(status: PackListStatus.loaded, packs: [])],
  );
}
