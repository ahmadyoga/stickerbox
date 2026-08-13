import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../blocs/import/import_bloc.dart';
import '../blocs/pack_detail/pack_detail_bloc.dart';
import '../blocs/pack_detail/pack_detail_event.dart';
import '../blocs/pack_detail/pack_detail_state.dart';
import '../repositories/import_repository.dart';
import '../repositories/link_thumbnail_fetcher.dart';
import '../repositories/sticker_processor.dart';
import '../repositories/whatsapp_handoff.dart';
import '../widgets/sticker_grid_tile.dart';
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

  Future<void> _setTrayIcon(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    );
    if (cropped == null || !context.mounted) return;
    context.read<PackDetailBloc>().add(TrayIconSet(cropped.path));
  }

  Future<void> _addToWhatsApp(BuildContext context, PackDetailLoaded state) async {
    final handoff = context.read<WhatsAppHandoff>();
    if (!await handoff.isWhatsAppInstalled()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('WhatsApp is not installed')),
        );
      }
      return;
    }
    await handoff.addPack(state.pack);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PackDetailBloc, PackDetailState>(
      builder: (context, state) {
        if (state is PackDetailNotFound) {
          return const Scaffold(body: Center(child: Text('Pack not found')));
        }
        if (state is! PackDetailLoaded) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(state.pack.name),
            actions: [
              IconButton(icon: const Icon(Icons.image), onPressed: () => _setTrayIcon(context)),
            ],
          ),
          body: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
            itemCount: state.pack.stickers.length,
            itemBuilder: (context, index) {
              final sticker = state.pack.stickers[index];
              return StickerGridTile(
                filePath: sticker.filePath,
                onRemove: () => context.read<PackDetailBloc>().add(StickerRemoved(sticker.id)),
              );
            },
          ),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FloatingActionButton(
                heroTag: 'add-sticker',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider(
                      create: (context) => ImportBloc(
                        importRepository: ImportRepository(),
                        stickerProcessor: context.read<StickerProcessor>(),
                        thumbnailFetcher: LinkThumbnailFetcher(),
                      ),
                      child: ImportScreen(packId: widget.packId),
                    ),
                  ),
                ),
                child: const Icon(Icons.add_photo_alternate),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'add-to-whatsapp',
                onPressed: state.canAddToWhatsApp ? () => _addToWhatsApp(context, state) : null,
                label: const Text('Add to WhatsApp'),
                icon: const Icon(Icons.chat),
              ),
            ],
          ),
        );
      },
    );
  }
}
