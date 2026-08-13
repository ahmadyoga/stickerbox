import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/pack_list/pack_list_bloc.dart';
import '../blocs/pack_list/pack_list_event.dart';
import '../blocs/pack_list/pack_list_state.dart';
import '../blocs/pack_detail/pack_detail_bloc.dart';
import '../repositories/pack_repository.dart';
import '../repositories/sticker_processor.dart';
import '../widgets/pack_list_tile.dart';
import 'pack_detail_screen.dart';

class PackListScreen extends StatelessWidget {
  const PackListScreen({super.key});

  Future<void> _createPack(BuildContext context) async {
    final nameController = TextEditingController();
    final publisherController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New pack'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Pack name')),
            TextField(controller: publisherController, decoration: const InputDecoration(labelText: 'Publisher')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create')),
        ],
      ),
    );
    if (created == true && nameController.text.trim().isNotEmpty && context.mounted) {
      context.read<PackListBloc>().add(
            PackCreated(nameController.text.trim(), publisherController.text.trim()),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sticker Packs')),
      body: BlocBuilder<PackListBloc, PackListState>(
        builder: (context, state) {
          if (state is! PackListLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.packs.isEmpty) {
            return const Center(child: Text('No packs yet. Tap + to create one.'));
          }
          return ListView.builder(
            itemCount: state.packs.length,
            itemBuilder: (context, index) {
              final pack = state.packs[index];
              return PackListTile(
                pack: pack,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BlocProvider(
                      create: (context) => PackDetailBloc(
                        repository: context.read<PackRepository>(),
                        stickerProcessor: context.read<StickerProcessor>(),
                      ),
                      child: PackDetailScreen(packId: pack.id),
                    ),
                  ),
                ),
                onDelete: () => context.read<PackListBloc>().add(PackDeleted(pack.id)),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPack(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
