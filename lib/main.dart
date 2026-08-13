import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

import 'blocs/pack_list/pack_list_bloc.dart';
import 'blocs/pack_list/pack_list_event.dart';
import 'hive/hive_setup.dart';
import 'models/sticker_pack.dart';
import 'repositories/pack_repository.dart';
import 'repositories/sticker_processor.dart';
import 'repositories/whatsapp_handoff.dart';
import 'screens/pack_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final box = await setUpHive();
  runApp(StickerCreatorApp(packsBox: box));
}

class StickerCreatorApp extends StatelessWidget {
  const StickerCreatorApp({super.key, required this.packsBox});

  final Box<StickerPack> packsBox;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => PackRepository(packsBox)),
        RepositoryProvider(create: (_) => StickerProcessor()),
        RepositoryProvider(create: (_) => WhatsAppHandoff()),
      ],
      child: Builder(
        builder: (context) => MaterialApp(
          title: 'Sticker Creator',
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
          home: BlocProvider(
            create: (context) => PackListBloc(context.read<PackRepository>())
              ..add(const PackListLoadRequested()),
            child: const PackListScreen(),
          ),
        ),
      ),
    );
  }
}
