import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/import/import_bloc.dart';
import '../blocs/import/import_event.dart';
import '../blocs/import/import_state.dart';
import '../blocs/pack_list/pack_list_bloc.dart';
import '../blocs/pack_list/pack_list_state.dart';
import '../theme.dart';

class ImportLinkSheet extends StatefulWidget {
  const ImportLinkSheet({super.key, required this.url});

  final String url;

  @override
  State<ImportLinkSheet> createState() => _ImportLinkSheetState();
}

class _ImportLinkSheetState extends State<ImportLinkSheet> {
  final Set<int> _selectedIndices = {};
  String? _selectedPackId;
  bool _createNewPack = false;
  final _newPackNameController = TextEditingController();
  final _newPackPublisherController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Start fetching thumbnails immediately
    context.read<ImportBloc>().add(LinkUrlSubmitted(widget.url));
  }

  @override
  void dispose() {
    _newPackNameController.dispose();
    _newPackPublisherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    
    return Container(
      decoration: BoxDecoration(
        color: colors.surf,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: colors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Import from Link',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Baloo 2',
                        color: colors.tx,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImageSelection(colors),
                    const SizedBox(height: 24),
                    _buildPackSelection(colors),
                    const SizedBox(height: 24),
                    _buildActionButtons(colors),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSelection(AppColors colors) {
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
        if (state.status == ImportStatus.processing) {
          return Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            child: Column(
              children: [
                CircularProgressIndicator(color: colors.acc),
                const SizedBox(height: 16),
                Text(
                  'Fetching images...',
                  style: TextStyle(color: colors.mut, fontSize: 14),
                ),
              ],
            ),
          );
        }

        if (state.status == ImportStatus.failure) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surf,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 48, color: colors.mut),
                const SizedBox(height: 12),
                Text(
                  state.failureMessage ?? 'Failed to fetch images',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: colors.mut),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => context.read<ImportBloc>().add(LinkUrlSubmitted(widget.url)),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          );
        }

        if (state.status == ImportStatus.thumbnailPreview && state.thumbnailPaths != null) {
          final paths = state.thumbnailPaths!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SELECT IMAGES',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colors.mut),
              ),
              const SizedBox(height: 12),
              if (paths.length == 1)
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.acc, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(File(paths[0]), fit: BoxFit.cover),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: paths.length,
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
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected ? colors.acc : colors.line,
                                width: selected ? 3 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(File(paths[index]), fit: BoxFit.cover),
                            ),
                          ),
                          if (selected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: colors.acc,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.check, size: 16, color: colors.accTx),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Text(
                '${_selectedIndices.length} of ${paths.length} selected',
                style: TextStyle(fontSize: 13, color: colors.mut),
              ),
            ],
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildPackSelection(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ADD TO PACK',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: colors.mut),
        ),
        const SizedBox(height: 12),
        
        // Create new pack option
        GestureDetector(
          onTap: () => setState(() {
            _createNewPack = true;
            _selectedPackId = null;
          }),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _createNewPack ? colors.accSoft : colors.surf,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _createNewPack ? colors.acc : colors.line,
                width: _createNewPack ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: _createNewPack ? colors.acc : colors.mut,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Create New Pack',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _createNewPack ? colors.tx : colors.mut,
                    ),
                  ),
                ),
                if (_createNewPack)
                  Icon(Icons.check_circle, color: colors.acc),
              ],
            ),
          ),
        ),
        
        // Show new pack form if selected
        if (_createNewPack) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surf2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pack Name',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.mut),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _newPackNameController,
                  decoration: const InputDecoration(
                    hintText: 'My Stickers',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Author (optional)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.mut),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _newPackPublisherController,
                  decoration: const InputDecoration(
                    hintText: 'Your name',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ],
        
        const SizedBox(height: 12),
        
        // Existing packs
        BlocBuilder<PackListBloc, PackListState>(
          builder: (context, state) {
            if (state.status != PackListStatus.loaded) {
              return const SizedBox.shrink();
            }
            
            if (state.packs.isEmpty) {
              return Text(
                'No existing packs available',
                style: TextStyle(fontSize: 13, color: colors.mut, fontStyle: FontStyle.italic),
              );
            }
            
            return Column(
              children: state.packs.map((pack) {
                final selected = _selectedPackId == pack.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedPackId = pack.id;
                      _createNewPack = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected ? colors.accSoft : colors.surf,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? colors.acc : colors.line,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pack.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: selected ? colors.tx : colors.mut,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${pack.stickers.length} stickers',
                                  style: TextStyle(fontSize: 12, color: colors.mut),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle, color: colors.acc),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionButtons(AppColors colors) {
    return BlocBuilder<ImportBloc, ImportState>(
      builder: (context, state) {
        final canProceed = state.status == ImportStatus.thumbnailPreview &&
            _selectedIndices.isNotEmpty &&
            (_selectedPackId != null || (_createNewPack && _newPackNameController.text.trim().isNotEmpty));

        return SizedBox(
          width: double.infinity,
          height: 58,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.acc,
              foregroundColor: colors.accTx,
              shape: const StadiumBorder(),
            ),
            onPressed: canProceed ? _handleConfirm : null,
            child: Text(
              _selectedIndices.length > 1 
                  ? 'Add ${_selectedIndices.length} Stickers' 
                  : 'Add Sticker',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }

  void _handleConfirm() {
    final importBloc = context.read<ImportBloc>();
    final state = importBloc.state;
    
    if (state.thumbnailPaths == null) return;
    
    final paths = state.thumbnailPaths!;
    final selected = paths.length == 1
        ? paths
        : (_selectedIndices.toList()..sort()).map((i) => paths[i]).toList();
    
    // Return the result
    Navigator.of(context).pop({
      'thumbnailPaths': selected,
      'createNewPack': _createNewPack,
      'packId': _selectedPackId,
      'newPackName': _newPackNameController.text.trim(),
      'newPackPublisher': _newPackPublisherController.text.trim(),
    });
  }
}
