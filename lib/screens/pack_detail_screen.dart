import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../blocs/import/import_bloc.dart';
import '../blocs/pack_detail/pack_detail_bloc.dart';
import '../blocs/pack_detail/pack_detail_event.dart';
import '../blocs/pack_detail/pack_detail_state.dart';
import '../blocs/theme/theme_cubit.dart';
import '../models/sticker.dart';
import '../repositories/import_repository.dart';
import '../repositories/link_thumbnail_fetcher.dart';
import '../repositories/sticker_processor.dart';
import '../repositories/whatsapp_handoff.dart';
import '../theme.dart';
import '../widgets/app_sheet.dart';
import '../widgets/sticker_grid_tile.dart';
import '../widgets/toast.dart';
import 'crop_screen.dart';
import 'import_screen.dart';

class PackDetailScreen extends StatefulWidget {
  const PackDetailScreen({super.key, required this.packId});

  final String packId;

  @override
  State<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends State<PackDetailScreen> {
  @override
  void initState() {
    super.initState();
    context.read<PackDetailBloc>().add(PackDetailLoadRequested(widget.packId));
  }

  Future<void> _pickAndCrop(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;
    final packDetailBloc = context.read<PackDetailBloc>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: packDetailBloc,
          child: CropScreen(sourcePath: picked.path),
        ),
      ),
    );
  }

  void _openImportScreen(BuildContext context) {
    final packDetailBloc = context.read<PackDetailBloc>();
    final importBloc = context.read<ImportBloc>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: packDetailBloc),
            BlocProvider.value(value: importBloc),
          ],
          child: ImportScreen(packId: widget.packId),
        ),
      ),
    );
  }

  Future<String?> _openOverflowSheet(BuildContext context, String packName) {
    return showAppSheet<String>(context, (sheetContext) {
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
                  packName,
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
  }

  Future<void> _openRenameSheet(BuildContext context, String currentName) async {
    final nameController = TextEditingController(text: currentName);
    final bloc = context.read<PackDetailBloc>();
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
                  bloc.add(PackRenameRequested(name));
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

  Future<void> _handleOverflow(BuildContext context, String packName) async {
    final bloc = context.read<PackDetailBloc>();
    final action = await _openOverflowSheet(context, packName);
    if (action == 'rename' && context.mounted) {
      await _openRenameSheet(context, packName);
    } else if (action == 'delete') {
      bloc.add(const PackDeleteRequested());
    }
  }

  Widget _bottomCta(BuildContext context, PackDetailState state) {
    final colors = Theme.of(context).extension<AppColors>()!;
    if (state.canAddToWhatsApp) {
      return SizedBox(
        height: 58,
        child: ElevatedButton(
          onPressed: () => _openWaConfirmSheet(context, state),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.acc,
            foregroundColor: colors.accTx,
            shape: const StadiumBorder(),
          ),
          child: const Text('Add to WhatsApp', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      );
    }
    final n = state.pack!.stickers.length;
    final noTray = state.pack!.trayIconPath == null;
    final help = noTray && n < 3
        ? 'Add 3–30 stickers and set a tray icon to continue.'
        : noTray
            ? 'Set a tray icon to continue.'
            : n < 3
                ? 'Add at least 3 stickers to continue.'
                : 'Remove stickers to get back under 30.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: colors.surf2, borderRadius: BorderRadius.circular(999)),
          child: Text(
            'Add to WhatsApp',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.mut),
          ),
        ),
        const SizedBox(height: 9),
        Text(help, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: colors.mut)),
      ],
    );
  }

  // Placeholder wired up fully in Task 10 — kept here so this task compiles
  // and the button above has somewhere real to call.
  void _openWaConfirmSheet(BuildContext context, PackDetailState state) {}

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ImportBloc(
        importRepository: ImportRepository(),
        stickerProcessor: context.read<StickerProcessor>(),
        thumbnailFetcher: LinkThumbnailFetcher(),
      ),
      child: BlocListener<PackDetailBloc, PackDetailState>(
        listenWhen: (previous, current) =>
            previous.status == PackDetailStatus.loaded && current.status == PackDetailStatus.notFound,
        listener: (context, state) {
          Navigator.of(context).pop();
          showToast(context, 'Pack deleted');
        },
        child: BlocBuilder<PackDetailBloc, PackDetailState>(
          builder: (context, state) {
            final colors = Theme.of(context).extension<AppColors>()!;
            if (state.status == PackDetailStatus.notFound) {
              return const Scaffold(body: Center(child: Text('Pack not found')));
            }
            if (state.status != PackDetailStatus.loaded) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final pack = state.pack!;
            final n = pack.stickers.length;
            return Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Expanded(
                            child: Text(
                              pack.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: colors.tx),
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
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _handleOverflow(context, pack.name),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 170),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: colors.surf,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: colors.line),
                            ),
                            child: Row(
                              children: [
                                pack.trayIconPath != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: Image.file(
                                          File(pack.trayIconPath!),
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Container(
                                        width: 60,
                                        height: 60,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(color: colors.acc, width: 1.5),
                                          color: colors.accSoft,
                                        ),
                                        child: Icon(Icons.add, color: colors.acc),
                                      ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tray icon',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: colors.tx,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        pack.trayIconPath != null ? '96×96 · PNG' : 'Not set yet',
                                        style: TextStyle(fontSize: 12.5, color: colors.mut),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => _pickAndCrop(context),
                                  child: Text(pack.trayIconPath != null ? 'Change' : 'Set icon'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text.rich(
                                TextSpan(
                                  text: 'Stickers ',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.tx),
                                  children: [
                                    TextSpan(
                                      text: '$n / 30',
                                      style: TextStyle(color: colors.mut, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              if (n < 30)
                                TextButton(
                                  onPressed: () => _openImportScreen(context),
                                  style: TextButton.styleFrom(
                                    backgroundColor: colors.accSoft,
                                    foregroundColor: colors.acc,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: const Text('+ Add'),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: colors.surf2,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('Pack full', style: TextStyle(color: colors.mut)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (n == 0)
                            Container(
                              padding: const EdgeInsets.fromLTRB(26, 32, 26, 34),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: colors.line, width: 2),
                              ),
                              child: Column(
                                children: [
                                  Image.asset('assets/icon.png', width: 120, height: 120),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Your pocket is empty',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: colors.tx,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Add your first sticker and start building a pack. Packs need at least 3.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13.5, color: colors.mut),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: () => _openImportScreen(context),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colors.acc,
                                      foregroundColor: colors.accTx,
                                      shape: const StadiumBorder(),
                                    ),
                                    child: const Text('Add Stickers'),
                                  ),
                                ],
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                              ),
                              itemCount: pack.stickers.length,
                              itemBuilder: (context, index) {
                                final sticker = pack.stickers[index];
                                return StickerGridTile(
                                  filePath: sticker.filePath,
                                  isAnimated: sticker.type == StickerType.animated,
                                  onRemove: () {
                                    context.read<PackDetailBloc>().add(StickerRemoved(sticker.id));
                                    showToast(context, 'Sticker removed');
                                  },
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                child: _bottomCta(context, state),
              ),
            );
          },
        ),
      ),
    );
  }
}
