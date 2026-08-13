import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/import/import_bloc.dart';
import '../blocs/import/import_event.dart';
import '../blocs/import/import_state.dart';
import '../blocs/pack_detail/pack_detail_bloc.dart';
import '../blocs/pack_detail/pack_detail_event.dart';
import '../models/sticker.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.packId});

  final String packId;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();

  // ImportReady carries only file paths, not a sticker type, so we track
  // which pick path is in flight to know what type to report on success.
  // Everything except the GIF path yields static stickers.
  StickerType _pendingType = StickerType.static_;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add stickers'),
          bottom: const TabBar(tabs: [Tab(text: 'From device'), Tab(text: 'From a link')]),
        ),
        body: BlocConsumer<ImportBloc, ImportState>(
          listener: (context, state) {
            if (state is ImportReady) {
              context.read<PackDetailBloc>().add(
                    StickersAdded(state.processedFilePaths, _pendingType),
                  );
              Navigator.of(context).pop();
            } else if (state is ImportFailure) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
            }
          },
          builder: (context, state) {
            if (state is ImportProcessing) {
              return const Center(child: CircularProgressIndicator());
            }
            return TabBarView(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          _pendingType = StickerType.static_;
                          context.read<ImportBloc>().add(const PickStaticImagesRequested());
                        },
                        child: const Text('Pick images'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          _pendingType = StickerType.animated;
                          context.read<ImportBloc>().add(const PickGifRequested());
                        },
                        child: const Text('Pick a GIF'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Paste a TikTok, Instagram, or Pinterest link',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (state is ImportThumbnailPreview) ...[
                        Image.file(_asFile(state.localPreviewPath), height: 200),
                        ElevatedButton(
                          onPressed: () {
                            _pendingType = StickerType.static_;
                            context.read<ImportBloc>().add(const LinkThumbnailConfirmed());
                          },
                          child: const Text('Use this image'),
                        ),
                      ] else
                        ElevatedButton(
                          onPressed: () => context
                              .read<ImportBloc>()
                              .add(LinkUrlSubmitted(_urlController.text.trim())),
                          child: const Text('Fetch preview'),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

File _asFile(String path) => File(path);
