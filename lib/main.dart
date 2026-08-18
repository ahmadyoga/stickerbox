import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';

import 'blocs/pack_list/pack_list_bloc.dart';
import 'blocs/pack_list/pack_list_event.dart';
import 'blocs/theme/theme_cubit.dart';
import 'hive/hive_setup.dart';
import 'models/sticker_pack.dart';
import 'repositories/pack_repository.dart';
import 'repositories/sticker_processor.dart';
import 'repositories/whatsapp_handoff.dart';
import 'screens/pack_list_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Nothing leaves the device: never fetch Nunito from Google's CDN. Falls back
  // to the platform font until the font is bundled as a local asset.
  GoogleFonts.config.allowRuntimeFetching = false;
  final box = await setUpHive();
  final settingsBox = await setUpSettingsBox();
  runApp(StickerCreatorApp(packsBox: box, settingsBox: settingsBox));
}

class StickerCreatorApp extends StatelessWidget {
  const StickerCreatorApp({super.key, required this.packsBox, required this.settingsBox});

  final Box<StickerPack> packsBox;
  final Box settingsBox;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => PackRepository(packsBox)),
        RepositoryProvider(create: (_) => StickerProcessor()),
        RepositoryProvider(create: (_) => WhatsAppHandoff()),
      ],
      child: BlocProvider(
        create: (_) => ThemeCubit(settingsBox),
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) => MaterialApp(
            title: 'Stickerbox',
            theme: buildTheme(dark: false),
            darkTheme: buildTheme(dark: true),
            themeMode: themeMode,
            home: BlocProvider(
              create: (context) => PackListBloc(context.read<PackRepository>())
                ..add(const PackListLoadRequested()),
              child: const PackListScreen(),
            ),
          ),
        ),
      ),
    );
  }
}
