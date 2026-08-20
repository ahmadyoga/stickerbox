import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../blocs/import/import_bloc.dart';
import '../blocs/import/import_event.dart';
import '../blocs/import/import_state.dart';
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
  const PackDetailScreen({super.key, required this.packId, this.pendingThumbnailPaths});

  final String packId;

  /// Thumbnails already fetched from a shared link (e.g. via the share-intent
  /// bottom sheet) that should be encoded into this pack as soon as it opens.
  final List<String>? pendingThumbnailPaths;

  @override
  State<PackDetailScreen> createState() => _PackDetailScreenState();
}

class _PackDetailScreenState extends State<PackDetailScreen> {
  bool _procSheetOpen = false;

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

  Future<void> _showStickerOptions(BuildContext context, String stickerPath) async {
    final colors = Theme.of(context).extension<AppColors>()!;
    final action = await showAppSheet<String>(
      context,
      (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sheetDragHandle(context),
            const SizedBox(height: 18),
            Text(
              'Sticker Options',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.tx),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: () => Navigator.of(sheetContext).pop('use_as_tray'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.line),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Use as Tray Icon',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.tx),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (action == 'use_as_tray' && context.mounted) {
      final packDetailBloc = context.read<PackDetailBloc>();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BlocProvider.value(
            value: packDetailBloc,
            child: CropScreen(sourcePath: stickerPath),
          ),
        ),
      );
    }
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
            Text(
              'Rename pack',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                fontFamily: 'Baloo 2',
                color: colors.tx,
              ),
            ),
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

  void _openProcessingSheetIfNeeded(BuildContext context) {
    if (_procSheetOpen) return;
    _procSheetOpen = true;
    // showAppSheet is a bare showModalBottomSheet: only InheritedTheme crosses
    // that boundary, so the ImportBloc has to be re-supplied by value.
    final importBloc = context.read<ImportBloc>();
    showAppSheet<void>(
      context,
      (sheetContext) => BlocProvider.value(
        value: importBloc,
        child: _ProcessingSheetContent(closeSelf: () {
          if (Navigator.of(sheetContext).canPop()) Navigator.of(sheetContext).pop();
        }),
      ),
    ).then((_) => _procSheetOpen = false);
  }

  /// Pops the processing sheet using PackDetail's own context. Only pops when
  /// something is still stacked above PackDetail — a manually-dragged-away sheet
  /// can leave `_procSheetOpen` true for a frame, and popping then would take
  /// PackDetailScreen itself with it.
  void _closeProcessingSheet(BuildContext context) {
    if (!_procSheetOpen || !context.mounted) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) return;
    Navigator.of(context).pop();
  }

  void _handleImportState(BuildContext context, ImportState state) {
    // The link tab stays open to show its own inline preview/error UI, so don't
    // stack the processing sheet on top of it.
    final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? false;
    switch (state.status) {
      case ImportStatus.processing:
      case ImportStatus.failure:
        if (isCurrentRoute) _openProcessingSheetIfNeeded(context);
      case ImportStatus.initial:
      case ImportStatus.thumbnailPreview:
        _closeProcessingSheet(context);
      case ImportStatus.ready:
        final paths = state.processedFilePaths!;
        if (paths.isEmpty) {
          _closeProcessingSheet(context);
          return;
        }
        context.read<PackDetailBloc>().add(StickersAdded(paths, state.type!));
        Future.delayed(const Duration(milliseconds: 950), () {
          if (!context.mounted) return;
          _closeProcessingSheet(context);
          showToast(
            context,
            paths.length > 1 ? '${paths.length} stickers added' : 'Sticker added',
          );
        });
    }
  }

  Future<void> _openWaConfirmSheet(BuildContext context, PackDetailState state) async {
    final handoff = context.read<WhatsAppHandoff>();
    final pack = state.pack!;
    await showAppSheet<void>(context, (sheetContext) {
      final colors = Theme.of(sheetContext).extension<AppColors>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sheetDragHandle(sheetContext),
            Text(
              'Add to WhatsApp',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                fontFamily: 'Baloo 2',
                color: colors.tx,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  if (pack.trayIconPath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.file(
                        File(pack.trayIconPath!),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.name,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.tx),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${pack.stickers.length} stickers · tray icon set',
                          style: TextStyle(fontSize: 13, color: colors.mut),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'WhatsApp will open to confirm. You can keep editing this pack afterwards.',
              style: TextStyle(fontSize: 13, color: colors.mut),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.acc,
                  foregroundColor: colors.accTx,
                  shape: const StadiumBorder(),
                ),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  try {
                    if (!await handoff.isWhatsAppInstalled()) {
                      if (context.mounted) _showWaMissingDialog(context);
                      return;
                    }
                    await handoff.addPack(pack);
                    if (context.mounted) _openWaSuccessSheet(context, pack.name);
                  } catch (_) {
                    if (context.mounted) {
                      _showWaDialog(
                        context,
                        'Something went wrong',
                        "Couldn't add to WhatsApp — please try again.",
                      );
                    }
                  }
                },
                child: const Text('Add to WhatsApp', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _openWaSuccessSheet(BuildContext context, String packName) {
    showAppSheet<void>(context, (sheetContext) {
      final colors = Theme.of(sheetContext).extension<AppColors>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sheetDragHandle(sheetContext),
            Icon(Icons.celebration_outlined, size: 64, color: colors.acc),
            const SizedBox(height: 16),
            Text(
              'Pack added to WhatsApp',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                fontFamily: 'Baloo 2',
                color: colors.tx,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '"$packName" is now available in your WhatsApp sticker tray.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: colors.mut),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.acc,
                  foregroundColor: colors.accTx,
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Back to pack', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showWaMissingDialog(BuildContext context) => _showWaDialog(
        context,
        "WhatsApp isn't installed",
        'This sticker pack can be added when WhatsApp is installed on your device.',
      );

  void _showWaDialog(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).extension<AppColors>()!;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Baloo 2',
                    color: colors.tx,
                  ),
                ),
                const SizedBox(height: 8),
                Text(body, style: TextStyle(fontSize: 14, color: colors.mut)),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.acc,
                      foregroundColor: colors.accTx,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final bloc = ImportBloc(
          importRepository: ImportRepository(),
          stickerProcessor: context.read<StickerProcessor>(),
          thumbnailFetcher: LinkThumbnailFetcher(),
        );
        final pending = widget.pendingThumbnailPaths;
        if (pending != null && pending.isNotEmpty) {
          bloc.add(LinkThumbnailConfirmed(pending));
        }
        return bloc;
      },
      child: MultiBlocListener(
        listeners: [
          BlocListener<PackDetailBloc, PackDetailState>(
            listenWhen: (previous, current) =>
                previous.status == PackDetailStatus.loaded && current.status == PackDetailStatus.notFound,
            listener: (context, state) {
              Navigator.of(context).pop();
              showToast(context, 'Pack deleted');
            },
          ),
          BlocListener<ImportBloc, ImportState>(listener: _handleImportState),
        ],
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
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontFamily: 'JetBrains Mono',
                                          color: colors.mut,
                                        ),
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
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                    if (n > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'Tap any sticker to use as tray icon',
                                          style: TextStyle(fontSize: 11.5, color: colors.mut),
                                        ),
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
                                      fontFamily: 'Baloo 2',
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
                                  onTap: () => _showStickerOptions(context, sticker.filePath),
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
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: _bottomCta(context, state),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProcessingSheetContent extends StatelessWidget {
  const _ProcessingSheetContent({required this.closeSelf});

  final VoidCallback closeSelf;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ImportBloc, ImportState>(
      builder: (context, state) {
        final colors = Theme.of(context).extension<AppColors>()!;
        final busy = state.status == ImportStatus.processing;
        final failed = state.status == ImportStatus.failure;
        final total = state.total;
        final current = state.current;
        final title = failed
            ? "Couldn't add sticker"
            : total != null && total > 1
                ? 'Adding stickers'
                : 'Preparing your sticker…';
        final subtitle = failed
            ? state.failureMessage ?? ''
            : total != null && total > 1
                ? '${current ?? 1} of $total'
                : 'Resizing to 512×512 and converting to WebP';
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              sheetDragHandle(context),
              Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: colors.tx)),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: colors.mut),
              ),
              if (busy) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total != null ? (current ?? 0) / total : null,
                    minHeight: 6,
                    backgroundColor: colors.surf2,
                    color: colors.acc,
                  ),
                ),
              ],
              if (failed) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.acc,
                          foregroundColor: colors.accTx,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: closeSelf,
                        child: const Text('Close — retry from the Import screen'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
