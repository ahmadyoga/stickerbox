import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/pack_detail/pack_detail_bloc.dart';
import '../blocs/pack_list/pack_list_bloc.dart';
import '../blocs/pack_list/pack_list_event.dart';
import '../blocs/pack_list/pack_list_state.dart';
import '../blocs/theme/theme_cubit.dart';
import '../models/sticker_pack.dart';
import '../repositories/pack_repository.dart';
import '../repositories/sticker_processor.dart';
import '../theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/pack_list_tile.dart';
import 'pack_detail_screen.dart';

class PackListScreen extends StatelessWidget {
  const PackListScreen({super.key});

  Future<void> _openCreateSheet(BuildContext context) async {
    final nameController = TextEditingController();
    final publisherController = TextEditingController();
    final packListBloc = context.read<PackListBloc>();
    await showAppSheet<void>(context, (sheetContext) {
      final colors = Theme.of(sheetContext).extension<AppColors>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetDragHandle(sheetContext),
            Text('New pack', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: colors.tx)),
            const SizedBox(height: 18),
            Text('PACK NAME', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colors.mut)),
            const SizedBox(height: 6),
            TextField(controller: nameController, autofocus: true),
            const SizedBox(height: 14),
            Text(
              'AUTHOR (optional)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colors.mut),
            ),
            const SizedBox(height: 6),
            TextField(controller: publisherController),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.acc,
                  foregroundColor: colors.accTx,
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  packListBloc.add(PackCreated(name, publisherController.text.trim()));
                  Navigator.of(sheetContext).pop();
                },
                child: const Text('Create Pack', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _openRenameSheet(BuildContext context, StickerPack pack) async {
    final nameController = TextEditingController(text: pack.name);
    final packListBloc = context.read<PackListBloc>();
    await showAppSheet<void>(context, (sheetContext) {
      final colors = Theme.of(sheetContext).extension<AppColors>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetDragHandle(sheetContext),
            Text('Rename pack', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: colors.tx)),
            const SizedBox(height: 18),
            TextField(controller: nameController, autofocus: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.acc,
                  foregroundColor: colors.accTx,
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  packListBloc.add(PackRenamed(pack.id, name));
                  Navigator.of(sheetContext).pop();
                },
                child: const Text('Save', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _openOverflowSheet(BuildContext context, StickerPack pack) async {
    final packListBloc = context.read<PackListBloc>();
    final action = await showAppSheet<String>(context, (sheetContext) {
      final colors = Theme.of(sheetContext).extension<AppColors>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sheetDragHandle(sheetContext),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  pack.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.mut),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.of(sheetContext).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFE0523C)),
              title: const Text('Delete pack', style: TextStyle(color: Color(0xFFE0523C))),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      );
    });
    if (action == 'rename' && context.mounted) {
      await _openRenameSheet(context, pack);
    } else if (action == 'delete') {
      packListBloc.add(PackDeleted(pack.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<PackListBloc, PackListState>(
          builder: (context, state) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stickerbox',
                              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800, color: colors.tx),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              state.status == PackListStatus.loaded && state.packs.isNotEmpty
                                  ? '${state.packs.length} packs · stored on this device'
                                  : 'Stored on this device',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.mut),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.read<ThemeCubit>().toggle(),
                        icon: Icon(
                          Theme.of(context).brightness == Brightness.dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: state.status != PackListStatus.loaded
                      ? const Center(child: CircularProgressIndicator())
                      : state.packs.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 44),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset('assets/icon.png', width: 160, height: 160),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Your pocket is empty',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: colors.tx,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Add your first sticker and start building a pack. Everything stays on your phone.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: colors.mut,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(22, 6, 22, 120),
                              itemCount: state.packs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final pack = state.packs[index];
                                final packListBloc = context.read<PackListBloc>();
                                return PackListTile(
                                  pack: pack,
                                  onTap: () => Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (_) => BlocProvider(
                                            create: (context) => PackDetailBloc(
                                              repository: context.read<PackRepository>(),
                                              stickerProcessor: context.read<StickerProcessor>(),
                                            ),
                                            child: PackDetailScreen(packId: pack.id),
                                          ),
                                        ),
                                      )
                                      .then((_) => packListBloc.add(const PackListLoadRequested())),
                                  onMenu: () => _openOverflowSheet(context, pack),
                                );
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: SizedBox(
          height: 58,
          child: ElevatedButton.icon(
            onPressed: () => _openCreateSheet(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.acc,
              foregroundColor: colors.accTx,
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create Pack', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
