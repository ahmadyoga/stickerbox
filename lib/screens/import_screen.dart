import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/import/import_bloc.dart';
import '../blocs/import/import_event.dart';
import '../blocs/import/import_state.dart';
import '../theme.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.packId});

  final String packId;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _urlController = TextEditingController();
  bool _onDeviceTab = true;
  final Set<int> _selectedIndices = {};

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _dispatchAndClose(ImportEvent event) {
    context.read<ImportBloc>().add(event);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
                  Text(
                    'Add stickers',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: colors.tx),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: colors.surf2, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    Expanded(
                      child: _TabButton(
                        label: 'From Device',
                        selected: _onDeviceTab,
                        onTap: () => setState(() => _onDeviceTab = true),
                      ),
                    ),
                    Expanded(
                      child: _TabButton(
                        label: 'From Link',
                        selected: !_onDeviceTab,
                        onTap: () => setState(() => _onDeviceTab = false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
                child: _onDeviceTab ? _buildDeviceTab(context) : _buildLinkTab(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTab(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Column(
      children: [
        _PickCard(
          title: 'Pick from your gallery',
          subtitle: 'Choose one or more images to pop into your pocket.',
          leading: Icon(Icons.photo_library_outlined, color: colors.acc),
          onTap: () => _dispatchAndClose(const PickStaticImagesRequested()),
        ),
        const SizedBox(height: 12),
        _PickCard(
          title: 'Bring in a GIF',
          subtitle: 'GIFs always come in as animated stickers.',
          leading: Text(
            'GIF',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono', color: colors.tx),
          ),
          onTap: () => _dispatchAndClose(const PickGifRequested()),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: colors.surf2, borderRadius: BorderRadius.circular(18)),
          child: Text(
            'Stickers are resized and compressed for WhatsApp automatically. Nothing leaves your device.',
            style: TextStyle(fontSize: 12.5, color: colors.mut),
          ),
        ),
      ],
    );
  }

  Widget _buildLinkTab(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return BlocConsumer<ImportBloc, ImportState>(
      listenWhen: (previous, current) =>
          current.status == ImportStatus.thumbnailPreview &&
          !identical(previous.thumbnailPaths, current.thumbnailPaths),
      listener: (context, state) {
        setState(() {
          _selectedIndices
            ..clear()
            ..addAll(List.generate(state.thumbnailPaths!.length, (i) => i));
        });
      },
      builder: (context, state) {
        final hasText = _urlController.text.trim().isNotEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Bring a sticker from the web',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: hasText ? colors.acc : colors.line, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                OutlinedButton(
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _urlController.text = data!.text!;
                      setState(() {});
                    }
                  },
                  child: const Text('Paste'),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              children: const [
                _SourceChip('TikTok'),
                _SourceChip('Instagram'),
                _SourceChip('Pinterest'),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasText ? colors.acc : colors.surf2,
                  foregroundColor: hasText ? colors.accTx : colors.mut,
                  shape: const StadiumBorder(),
                ),
                onPressed: hasText
                    ? () => context.read<ImportBloc>().add(LinkUrlSubmitted(_urlController.text.trim()))
                    : null,
                child: const Text('Import', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            if (state.status == ImportStatus.processing) ...[
              const SizedBox(height: 22),
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text('Finding your sticker…', style: TextStyle(fontSize: 14, color: colors.mut)),
                  ],
                ),
              ),
            ],
            if (state.status == ImportStatus.thumbnailPreview) ...[
              const SizedBox(height: 22),
              if (state.thumbnailPaths!.length == 1)
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.file(File(state.thumbnailPaths!.first), width: double.infinity, fit: BoxFit.cover),
                )
              else ...[
                Text(
                  'Found ${state.thumbnailPaths!.length} images — tap to pick which ones to add',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.mut),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: state.thumbnailPaths!.length,
                  itemBuilder: (context, index) {
                    final selected = _selectedIndices.contains(index);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (selected) {
                          _selectedIndices.remove(index);
                        } else {
                          _selectedIndices.add(index);
                        }
                      }),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Opacity(
                              opacity: selected ? 1 : 0.35,
                              child: Image.file(File(state.thumbnailPaths![index]), fit: BoxFit.cover),
                            ),
                          ),
                          if (selected)
                            Positioned(
                              right: 5,
                              top: 5,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(color: colors.acc, shape: BoxShape.circle),
                                child: const Icon(Icons.check, size: 14, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _urlController.clear()),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.acc,
                        foregroundColor: colors.accTx,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _selectedIndices.isEmpty
                          ? null
                          : () {
                              final paths = state.thumbnailPaths!;
                              final selected = paths.length == 1
                                  ? paths
                                  : (_selectedIndices.toList()..sort()).map((i) => paths[i]).toList();
                              _dispatchAndClose(LinkThumbnailConfirmed(selected));
                            },
                      child: Text(
                        _selectedIndices.length > 1 ? 'Add ${_selectedIndices.length} Stickers' : 'Add Sticker',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (state.status == ImportStatus.failure) ...[
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: colors.surf, borderRadius: BorderRadius.circular(26)),
                child: Column(
                  children: [
                    Text(
                      state.failureMessage ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: colors.mut),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton(
                      onPressed: () =>
                          context.read<ImportBloc>().add(LinkUrlSubmitted(_urlController.text.trim())),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? colors.surf : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: selected ? colors.tx : colors.mut,
          ),
        ),
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.title, required this.subtitle, required this.leading, required this.onTap});

  final String title;
  final String subtitle;
  final Widget leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.surf,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colors.accSoft, borderRadius: BorderRadius.circular(17)),
              child: leading,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: colors.tx)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: colors.mut)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(color: colors.surf2, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colors.mut)),
    );
  }
}
