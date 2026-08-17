# Design Import: Visual Redesign + Feature Additions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved design spec (`docs/superpowers/specs/2026-08-15-design-import-redesign.md`) — a full visual redesign of all three screens sourced from the `Sticker Pack App.dc.html` Claude Design mockup, plus dark mode, a custom crop screen, toast notifications, live import progress, rename/delete, and a new app icon — on top of the existing Flutter/Bloc app.

**Architecture:** Add a `ThemeCubit` + `AppColors` `ThemeExtension` as the design-token layer every redesigned widget reads from. Move `ImportBloc` from being scoped to the pushed `ImportScreen` route to living alongside `PackDetailBloc` at `PackDetailScreen`, so Import can pop immediately and Detail's new processing sheet can keep listening to it. Replace `image_cropper` with a themeable pure-Flutter cropper (`crop_your_image`) wrapped in a new `CropScreen`. Redesign each screen's widget tree in place; no new blocs beyond `ThemeCubit`, no new persistence beyond one Hive `settings` box.

**Tech Stack:** Flutter/Dart, flutter_bloc, Hive, `google_fonts` (Nunito/Baloo 2/JetBrains Mono, matching the mockup's Google Fonts), `flutter_launcher_icons` (app icon generation), `crop_your_image` (replaces `image_cropper`).

## Global Constraints

- Use `fvm flutter` / `fvm dart` for every command in this plan (this project pins Flutter via FVM — see `.fvmrc`), never bare `flutter`/`dart`.
- Accent color is fixed to `#FF6B57` in both light and dark mode — not a user-facing setting (spec: "Out of scope").
- Dark mode toggle is manual only, persisted to a Hive `settings` box under key `isDark` — no system-theme following.
- App display name changes to "Stickerbox" (UI text / `MaterialApp.title` only — package id and store identity are unchanged, per spec).
- `ImportProcessing`'s `current`/`total` fields are `null` for single-item flows (GIF pick, link import) and populated only during the static-image batch loop.
- Per this project's established testing convention (confirmed in the approved spec's own Testing section): bloc-level logic gets `bloc_test` coverage; pure UI (redesigned screens, new sheets, `CropScreen`) gets no automated tests — verify by running the app with `fvm flutter run`. Every UI-only task below still runs `fvm flutter analyze` before its commit.
- Follow this project's existing patterns: sealed `Equatable` events/states, `Bloc`'s `_mutate`-via-`repository.getPack`-then-save pattern in `PackDetailBloc`, the `BlocProvider.value` re-supply pattern for widgets pushed via `Navigator.push` (routes are Overlay siblings, not descendants — see `pack_detail_screen.dart`'s existing comment).

---

## File Structure

**New files:**
- `lib/theme.dart` — `AppColors` (`ThemeExtension`, light/dark token sets matching the mockup's `c_bg`/`c_surf`/etc.) + `buildTheme({required bool dark})`.
- `lib/blocs/theme/theme_cubit.dart` — `ThemeCubit extends Cubit<ThemeMode>`, persists to the `settings` Hive box.
- `lib/widgets/app_sheet.dart` — `showAppSheet<T>()` (shared bottom-sheet chrome: rounded top corners, themed background) + `sheetDragHandle()`. Used by every new sheet (create/rename/overflow/processing/WA confirm/WA success).
- `lib/widgets/toast.dart` — `showToast(context, message)`, a restyled dark pill `SnackBar`.
- `lib/screens/crop_screen.dart` — `CropScreen`, wraps `crop_your_image`'s `Crop` widget, dispatches `TrayIconSet` on confirm.

**Modified files:**
- `pubspec.yaml` — add `google_fonts`, `flutter_launcher_icons` (dev), `crop_your_image`; remove `image_cropper`; add `flutter_launcher_icons:` config; add `assets/icon.png` to `flutter: assets:`.
- `lib/hive/hive_setup.dart` — add `settingsBoxName` + `setUpSettingsBox()`.
- `lib/main.dart` — open the settings box, provide `ThemeCubit`, wire `theme`/`darkTheme`/`themeMode`, rename app title.
- `lib/blocs/pack_detail/pack_detail_event.dart` — add `PackRenameRequested`, `PackDeleteRequested`.
- `lib/blocs/pack_detail/pack_detail_bloc.dart` — handlers for the two new events.
- `lib/blocs/import/import_state.dart` — `ImportProcessing` gains `current`/`total`; `ImportReady` gains `type` (root-causes the `_pendingType` tracking that only worked because `ImportScreen` used to stay alive until `ImportReady` — it won't once Import pops immediately).
- `lib/blocs/import/import_bloc.dart` — emit progress during the static-image batch loop; pass the correct `StickerType` into every `ImportReady`.
- `lib/widgets/pack_list_tile.dart` — redesigned card (tray thumbnail/placeholder, meta, up to 4 mini previews, overflow button).
- `lib/widgets/sticker_grid_tile.dart` — redesigned tile (rounded border, GIF badge, dark remove chip); gains an `isAnimated` param.
- `lib/screens/pack_list_screen.dart` — full redesign: header, empty state, create-pack sheet, per-pack overflow (rename/delete) sheet.
- `lib/screens/pack_detail_screen.dart` — full redesign: header, tray card (→ `CropScreen`), sticker count header, empty state, grid, bottom CTA with helper text, overflow (rename/delete) sheet, processing sheet (live progress), WhatsApp confirm/success sheets, WhatsApp-missing dialog; provides `ImportBloc` at this level now.
- `lib/screens/import_screen.dart` — full redesign: segmented tabs, device tab, link tab; pops immediately on dispatch instead of waiting for `ImportReady`.
- `test/blocs/import_bloc_test.dart` — update for the new `ImportReady(paths, type)` signature and progress emissions.

---

## Task 1: Theme foundation — `AppColors`, `ThemeCubit`, `main.dart` wiring

**Files:**
- Create: `lib/theme.dart`
- Create: `lib/blocs/theme/theme_cubit.dart`
- Create: `test/blocs/theme_cubit_test.dart`
- Modify: `lib/hive/hive_setup.dart`
- Modify: `lib/main.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `AppColors` (`ThemeExtension<AppColors>`, static `light`/`dark` instances, fields `bg surf surf2 tx mut line acc accTx accSoft stick scrim accShadow` — all `Color`). `ThemeData buildTheme({required bool dark})`. `ThemeCubit(Box box)` with `void toggle()`. `settingsBoxName` (String), `Future<Box> setUpSettingsBox()`.
- Every later UI task reads colors via `Theme.of(context).extension<AppColors>()!`.

- [ ] **Step 1: Add `google_fonts` dependency**

Edit `pubspec.yaml`, in `dependencies:` (alongside `path: ^1.9.1`):

```yaml
  google_fonts: ^6.2.1
```

Run: `fvm flutter pub get`

- [ ] **Step 2: Write `lib/theme.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surf,
    required this.surf2,
    required this.tx,
    required this.mut,
    required this.line,
    required this.acc,
    required this.accTx,
    required this.accSoft,
    required this.stick,
    required this.scrim,
    required this.accShadow,
  });

  final Color bg;
  final Color surf;
  final Color surf2;
  final Color tx;
  final Color mut;
  final Color line;
  final Color acc;
  final Color accTx;
  final Color accSoft;
  final Color stick;
  final Color scrim;
  final Color accShadow;

  static const light = AppColors(
    bg: Color(0xFFFFF8F3),
    surf: Color(0xFFFFFFFF),
    surf2: Color(0xFFF6EEE8),
    tx: Color(0xFF2B2220),
    mut: Color(0xFF7C6F69),
    line: Color(0x142B2220),
    acc: Color(0xFFFF6B57),
    accTx: Color(0xFFFFFFFF),
    accSoft: Color(0xFFFFE7E0),
    stick: Color(0xFFFFFFFF),
    scrim: Color(0xC7FFF8F3),
    accShadow: Color(0x80FF6B57),
  );

  static const dark = AppColors(
    bg: Color(0xFF17120F),
    surf: Color(0xFF231C18),
    surf2: Color(0xFF2F2621),
    tx: Color(0xFFF8F1EC),
    mut: Color(0xFFA89A92),
    line: Color(0x1AFFFFFF),
    acc: Color(0xFFFF6B57),
    accTx: Color(0xFFFFFFFF),
    accSoft: Color(0x33FF6B57),
    stick: Color(0xFF3A2F29),
    scrim: Color(0xB817120F),
    accShadow: Color(0x8C000000),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surf,
    Color? surf2,
    Color? tx,
    Color? mut,
    Color? line,
    Color? acc,
    Color? accTx,
    Color? accSoft,
    Color? stick,
    Color? scrim,
    Color? accShadow,
  }) {
    return AppColors(
      bg: bg ?? this.bg,
      surf: surf ?? this.surf,
      surf2: surf2 ?? this.surf2,
      tx: tx ?? this.tx,
      mut: mut ?? this.mut,
      line: line ?? this.line,
      acc: acc ?? this.acc,
      accTx: accTx ?? this.accTx,
      accSoft: accSoft ?? this.accSoft,
      stick: stick ?? this.stick,
      scrim: scrim ?? this.scrim,
      accShadow: accShadow ?? this.accShadow,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surf: Color.lerp(surf, other.surf, t)!,
      surf2: Color.lerp(surf2, other.surf2, t)!,
      tx: Color.lerp(tx, other.tx, t)!,
      mut: Color.lerp(mut, other.mut, t)!,
      line: Color.lerp(line, other.line, t)!,
      acc: Color.lerp(acc, other.acc, t)!,
      accTx: Color.lerp(accTx, other.accTx, t)!,
      accSoft: Color.lerp(accSoft, other.accSoft, t)!,
      stick: Color.lerp(stick, other.stick, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      accShadow: Color.lerp(accShadow, other.accShadow, t)!,
    );
  }
}

ThemeData buildTheme({required bool dark}) {
  final colors = dark ? AppColors.dark : AppColors.light;
  final brightness = dark ? Brightness.dark : Brightness.light;
  final colorScheme = ColorScheme.fromSeed(seedColor: colors.acc, brightness: brightness).copyWith(
    primary: colors.acc,
    onPrimary: colors.accTx,
    surface: colors.surf,
    onSurface: colors.tx,
  );
  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: colorScheme,
    textTheme: GoogleFonts.nunitoTextTheme(ThemeData(brightness: brightness).textTheme).apply(
      bodyColor: colors.tx,
      displayColor: colors.tx,
    ),
    extensions: [colors],
  );
}
```

- [ ] **Step 3: Add the settings box to `lib/hive/hive_setup.dart`**

Append to the file:

```dart

const settingsBoxName = 'settings';

Future<Box> setUpSettingsBox() => Hive.openBox(settingsBoxName);
```

- [ ] **Step 4: Write `lib/blocs/theme/theme_cubit.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

const _isDarkKey = 'isDark';

class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this._box)
      : super(_box.get(_isDarkKey, defaultValue: false) == true ? ThemeMode.dark : ThemeMode.light);

  final Box _box;

  void toggle() {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    emit(next);
    _box.put(_isDarkKey, next == ThemeMode.dark);
  }
}
```

- [ ] **Step 5: Write the failing/characterizing tests**

Create `test/blocs/theme_cubit_test.dart`:

```dart
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sticker_creator/blocs/theme/theme_cubit.dart';

void main() {
  late Directory tempDir;
  late Box box;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('theme_cubit_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox('settings');
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('settings');
    tempDir.deleteSync(recursive: true);
  });

  test('defaults to light mode when no preference is persisted', () {
    final cubit = ThemeCubit(box);
    expect(cubit.state, ThemeMode.light);
  });

  test('reads a persisted dark preference on construction', () async {
    await box.put('isDark', true);
    final cubit = ThemeCubit(box);
    expect(cubit.state, ThemeMode.dark);
  });

  blocTest<ThemeCubit, ThemeMode>(
    'toggle flips the mode and persists it',
    build: () => ThemeCubit(box),
    act: (cubit) => cubit.toggle(),
    expect: () => [ThemeMode.dark],
    verify: (_) => expect(box.get('isDark'), isTrue),
  );
}
```

Run: `fvm flutter test test/blocs/theme_cubit_test.dart`
Expected: FAIL (no `theme_cubit.dart` errors expected since it already exists from Step 4 — if it fails here it's a real bug; fix before continuing).

- [ ] **Step 6: Run the test and confirm it passes**

Run: `fvm flutter test test/blocs/theme_cubit_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 7: Wire it into `lib/main.dart`**

Replace the full file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
```

- [ ] **Step 8: Run the full test suite and analyzer**

Run: `fvm flutter analyze && fvm flutter test`
Expected: analyzer clean; all tests pass (pre-existing suite plus the 3 new ones).

- [ ] **Step 9: Commit**

```bash
git add lib/theme.dart lib/blocs/theme/theme_cubit.dart lib/hive/hive_setup.dart lib/main.dart pubspec.yaml pubspec.lock test/blocs/theme_cubit_test.dart
git commit -m "Add ThemeCubit, AppColors theme tokens, and dark-mode persistence"
```

---

## Task 2: App icon + in-app logo asset

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: platform launcher icons generated from `assets/app-icon.png`; `assets/icon.png` available to `Image.asset('assets/icon.png')` for Task 8's empty states.

- [ ] **Step 1: Add `flutter_launcher_icons` and configure it**

Edit `pubspec.yaml`. In `dev_dependencies:`:

```yaml
  flutter_launcher_icons: ^0.14.3
```

Add a top-level section (after the `flutter:` block):

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/app-icon.png"
  min_sdk_android: 21
```

- [ ] **Step 2: Bundle the in-app logo asset**

In `pubspec.yaml`'s `flutter: assets:` list, add:

```yaml
    - assets/icon.png
```

(leave the existing `test/fixtures/sample.jpg` entry as-is)

- [ ] **Step 3: Fetch dependencies and generate icons**

Run: `fvm flutter pub get`
Run: `fvm dart run flutter_launcher_icons`
Expected: reports writing Android (`android/app/src/main/res/mipmap-*/ic_launcher.png`) and iOS (`ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`) icon files.

- [ ] **Step 4: Verify the build still succeeds**

Run: `fvm flutter analyze`
Run: `fvm flutter build apk --debug`
Expected: both succeed.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/res ios/Runner/Assets.xcassets
git commit -m "Generate app icon from assets/app-icon.png; bundle assets/icon.png as the in-app logo mark"
```

---

## Task 3: `PackDetailBloc` rename/delete events

**Files:**
- Modify: `lib/blocs/pack_detail/pack_detail_event.dart`
- Modify: `lib/blocs/pack_detail/pack_detail_bloc.dart`
- Modify: `test/blocs/pack_detail_bloc_test.dart`

**Interfaces:**
- Produces: `PackRenameRequested(String newName)`, `PackDeleteRequested()` events; on delete, bloc emits `PackDetailNotFound` (reused — Task 8's screen distinguishes "not found because just deleted" via `BlocListener.listenWhen: previous is PackDetailLoaded && current is PackDetailNotFound`).

- [ ] **Step 1: Write the failing tests**

Add to `test/blocs/pack_detail_bloc_test.dart` (before the final closing `}`):

```dart

  blocTest<PackDetailBloc, PackDetailState>(
    'PackRenameRequested renames and re-saves the pack',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png'));
      when(() => repository.savePack(any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailLoaded(_packWith(3, trayIconPath: '/tmp/tray.png'), true),
    act: (bloc) => bloc.add(const PackRenameRequested('New Name')),
    expect: () => [
      isA<PackDetailLoaded>().having((s) => s.pack.name, 'name', 'New Name'),
    ],
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      expect((captured.single as StickerPack).name, 'New Name');
    },
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'PackDeleteRequested deletes the pack and emits PackDetailNotFound',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png'));
      when(() => repository.deletePack('p1')).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailLoaded(_packWith(3, trayIconPath: '/tmp/tray.png'), true),
    act: (bloc) => bloc.add(const PackDeleteRequested()),
    expect: () => [const PackDetailNotFound()],
    verify: (_) => verify(() => repository.deletePack('p1')).called(1),
  );
```

Run: `fvm flutter test test/blocs/pack_detail_bloc_test.dart`
Expected: FAIL — `PackRenameRequested`/`PackDeleteRequested` undefined.

- [ ] **Step 2: Add the events**

Append to `lib/blocs/pack_detail/pack_detail_event.dart` (before the final closing brace of the file, i.e. after `TrayIconSet`):

```dart

class PackRenameRequested extends PackDetailEvent {
  const PackRenameRequested(this.newName);

  final String newName;

  @override
  List<Object?> get props => [newName];
}

class PackDeleteRequested extends PackDetailEvent {
  const PackDeleteRequested();
}
```

- [ ] **Step 3: Add the handlers**

In `lib/blocs/pack_detail/pack_detail_bloc.dart`, register the two new handlers in the constructor:

```dart
    on<PackDetailLoadRequested>(_onLoad);
    on<StickersAdded>(_onStickersAdded);
    on<StickerRemoved>(_onStickerRemoved);
    on<TrayIconSet>(_onTrayIconSet);
    on<PackRenameRequested>(_onRenameRequested);
    on<PackDeleteRequested>(_onDeleteRequested);
```

Add the two methods (after `_onTrayIconSet`):

```dart

  Future<void> _onRenameRequested(PackRenameRequested event, Emitter<PackDetailState> emit) =>
      _mutate(emit, (pack) => pack.name = event.newName);

  Future<void> _onDeleteRequested(PackDeleteRequested event, Emitter<PackDetailState> emit) async {
    final current = state;
    if (current is! PackDetailLoaded) return;
    await repository.deletePack(current.pack.id);
    emit(const PackDetailNotFound());
  }
```

- [ ] **Step 4: Run the tests**

Run: `fvm flutter test test/blocs/pack_detail_bloc_test.dart`
Expected: PASS (all tests, including the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add lib/blocs/pack_detail/pack_detail_event.dart lib/blocs/pack_detail/pack_detail_bloc.dart test/blocs/pack_detail_bloc_test.dart
git commit -m "Add PackDetailBloc rename/delete events for the Detail screen's overflow menu"
```

---

## Task 4: `ImportState` progress + type fields; `ImportBloc` updates

**Files:**
- Modify: `lib/blocs/import/import_state.dart`
- Modify: `lib/blocs/import/import_bloc.dart`
- Modify: `test/blocs/import_bloc_test.dart`

**Interfaces:**
- Produces: `ImportProcessing({int? current, int? total})`; `ImportReady(List<String> processedFilePaths, StickerType type)`. Task 8/9's `PackDetailScreen` listener reads `state.current`/`state.total` for the progress bar and `state.type` to dispatch `StickersAdded` with the right `StickerType` (replacing `ImportScreen`'s now-removed `_pendingType` field, which only worked while Import stayed alive until `ImportReady` — it won't once Task 10 makes Import pop immediately).

- [ ] **Step 1: Write the failing tests**

Replace `test/blocs/import_bloc_test.dart` in full:

```dart
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sticker_creator/blocs/import/import_bloc.dart';
import 'package:sticker_creator/blocs/import/import_event.dart';
import 'package:sticker_creator/blocs/import/import_state.dart';
import 'package:sticker_creator/models/sticker.dart';
import 'package:sticker_creator/repositories/import_repository.dart';
import 'package:sticker_creator/repositories/link_thumbnail_fetcher.dart';
import 'package:sticker_creator/repositories/sticker_processor.dart';

class MockImportRepository extends Mock implements ImportRepository {}

class MockStickerProcessor extends Mock implements StickerProcessor {}

class MockLinkThumbnailFetcher extends Mock implements LinkThumbnailFetcher {}

/// Fakes getApplicationDocumentsDirectory() so the bloc can run under plain
/// flutter_test without a real platform channel (see test/hive/hive_setup_test.dart
/// for the same pattern).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);

  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late MockImportRepository importRepository;
  late MockStickerProcessor stickerProcessor;
  late MockLinkThumbnailFetcher thumbnailFetcher;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue('');
  });

  setUp(() {
    importRepository = MockImportRepository();
    stickerProcessor = MockStickerProcessor();
    thumbnailFetcher = MockLinkThumbnailFetcher();
    tempDir = Directory.systemTemp.createTempSync('import_bloc_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ImportBloc buildBloc() => ImportBloc(
    importRepository: importRepository,
    stickerProcessor: stickerProcessor,
    thumbnailFetcher: thumbnailFetcher,
  );

  blocTest<ImportBloc, ImportState>(
    'PickStaticImagesRequested reports current/total progress per image and emits a static ImportReady',
    setUp: () {
      when(() => importRepository.pickStaticImages())
          .thenAnswer((_) async => ['/tmp/a.jpg', '/tmp/b.jpg']);
      when(() => stickerProcessor.encodeStatic(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickStaticImagesRequested()),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportProcessing(),
      const ImportProcessing(current: 1, total: 2),
      const ImportProcessing(current: 2, total: 2),
      isA<ImportReady>()
          .having((s) => s.processedFilePaths.length, 'processedFilePaths.length', 2)
          .having((s) => s.type, 'type', StickerType.static_),
    ],
    verify: (_) {
      verify(() => importRepository.pickStaticImages()).called(1);
      verify(() => stickerProcessor.encodeStatic('/tmp/a.jpg', any())).called(1);
      verify(() => stickerProcessor.encodeStatic('/tmp/b.jpg', any())).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'PickGifRequested processes the picked GIF and emits an animated ImportReady with no progress fields',
    setUp: () {
      when(() => importRepository.pickGifFile()).thenAnswer((_) async => '/tmp/a.gif');
      when(() => stickerProcessor.encodeAnimatedGif(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickGifRequested()),
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportProcessing(),
      isA<ImportReady>()
          .having((s) => s.processedFilePaths, 'processedFilePaths', ['/tmp/a.gif not used directly'])
          .having((s) => s.type, 'type', StickerType.animated),
    ],
    verify: (_) {
      verify(() => importRepository.pickGifFile()).called(1);
      verify(() => stickerProcessor.encodeAnimatedGif('/tmp/a.gif', any())).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'PickGifRequested returns to ImportInitial when the user cancels the picker',
    setUp: () {
      when(() => importRepository.pickGifFile()).thenAnswer((_) async => null);
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickGifRequested()),
    expect: () => [const ImportProcessing(), const ImportInitial()],
    verify: (_) {
      verifyNever(() => stickerProcessor.encodeAnimatedGif(any(), any()));
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted fetches and previews a thumbnail',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrl(any()),
      ).thenAnswer((_) async => 'https://example.com/thumb.jpg');
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    wait: const Duration(milliseconds: 50),
    expect: () => [const ImportProcessing(), isA<ImportThumbnailPreview>()],
    verify: (_) {
      verify(
        () => thumbnailFetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc'),
      ).called(1);
      verify(
        () => thumbnailFetcher.downloadImage('https://example.com/thumb.jpg', any()),
      ).called(1);
    },
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted emits ImportFailure when the fetcher throws',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrl(any()),
      ).thenThrow(LinkThumbnailException('No preview image found for this link'));
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    expect: () => [const ImportProcessing(), const ImportFailure('No preview image found for this link')],
  );

  blocTest<ImportBloc, ImportState>(
    'LinkThumbnailConfirmed encodes the previewed thumbnail and emits a static ImportReady',
    setUp: () {
      when(
        () => thumbnailFetcher.fetchThumbnailUrl(any()),
      ).thenAnswer((_) async => 'https://example.com/thumb.jpg');
      when(() => thumbnailFetcher.downloadImage(any(), any())).thenAnswer((_) async {});
      when(() => stickerProcessor.encodeStatic(any(), any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) async {
      bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc'));
      await bloc.stream.firstWhere((s) => s is ImportThumbnailPreview);
      bloc.add(const LinkThumbnailConfirmed());
    },
    wait: const Duration(milliseconds: 50),
    expect: () => [
      const ImportProcessing(),
      isA<ImportThumbnailPreview>(),
      const ImportProcessing(),
      isA<ImportReady>().having((s) => s.type, 'type', StickerType.static_),
    ],
    verify: (_) {
      verify(() => stickerProcessor.encodeStatic(any(), any())).called(1);
    },
  );
}
```

Note: the GIF test's `.having((s) => s.processedFilePaths, ...)` deliberately uses an obviously-wrong literal (`'/tmp/a.gif not used directly'`) — fix it in Step 2 below once you've confirmed the test fails for the *right* reason (missing `type` param), then correct it to `['/tmp/output-path-is-generated']`-style: actually assert only what's knowable — replace that `.having` line with `.having((s) => s.processedFilePaths.length, 'processedFilePaths.length', 1)` before running for real. Do this correction now, before Step 2, so the "run to see it fail" step fails only on the compile error, not on a wrong assertion.

Run: `fvm flutter test test/blocs/import_bloc_test.dart`
Expected: FAIL to compile — `ImportProcessing(current: ..., total: ...)` and `ImportReady`'s missing second positional arg don't exist yet.

- [ ] **Step 2: Update `ImportState`**

Replace `ImportProcessing` and `ImportReady` in `lib/blocs/import/import_state.dart`:

```dart
class ImportProcessing extends ImportState {
  const ImportProcessing({this.current, this.total});

  final int? current;
  final int? total;

  @override
  List<Object?> get props => [current, total];
}
```

```dart
class ImportReady extends ImportState {
  const ImportReady(this.processedFilePaths, this.type);

  final List<String> processedFilePaths;
  final StickerType type;

  @override
  List<Object?> get props => [processedFilePaths, type];
}
```

Add the import at the top of the file:

```dart
import '../../models/sticker.dart';
```

- [ ] **Step 3: Update `ImportBloc`**

In `lib/blocs/import/import_bloc.dart`, replace `_onPickStaticImages`:

```dart
  Future<void> _onPickStaticImages(
    PickStaticImagesRequested event,
    Emitter<ImportState> emit,
  ) async {
    emit(const ImportProcessing());
    try {
      final picked = await importRepository.pickStaticImages();
      final total = picked.length;
      final outputs = <String>[];
      for (var i = 0; i < picked.length; i++) {
        final outputPath = await _newOutputPath('webp');
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await stickerProcessor.encodeStatic(picked[i], outputPath);
        outputs.add(outputPath);
        emit(ImportProcessing(current: i + 1, total: total));
      }
      emit(ImportReady(outputs, StickerType.static_));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }
```

Replace the `emit(ImportReady([outputPath]));` line in `_onPickGif` with:

```dart
      emit(ImportReady([outputPath], StickerType.animated));
```

Replace the `emit(ImportReady([outputPath]));` line in `_onLinkThumbnailConfirmed` with:

```dart
      emit(ImportReady([outputPath], StickerType.static_));
```

Add the import at the top of the file:

```dart
import '../../models/sticker.dart';
```

- [ ] **Step 4: Run the tests**

Run: `fvm flutter test test/blocs/import_bloc_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the full suite**

Run: `fvm flutter analyze && fvm flutter test`
Expected: clean, all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/blocs/import/import_state.dart lib/blocs/import/import_bloc.dart test/blocs/import_bloc_test.dart
git commit -m "Add live progress fields to ImportProcessing and a type field to ImportReady"
```

---

## Task 5: Toast helper

**Files:**
- Create: `lib/widgets/toast.dart`
- Create: `test/widgets/toast_test.dart`

**Interfaces:**
- Produces: `void showToast(BuildContext context, String message)`. Used by Task 8/9 (e.g. "Sticker removed", "N stickers added", "Tray icon updated", "Pack deleted").

- [ ] **Step 1: Write the failing test**

Create `test/widgets/toast_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_creator/widgets/toast.dart';

void main() {
  testWidgets('showToast displays the message in a SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showToast(context, 'Sticker added'),
            child: const Text('trigger'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pump();

    expect(find.text('Sticker added'), findsOneWidget);
  });
}
```

Run: `fvm flutter test test/widgets/toast_test.dart`
Expected: FAIL — `package:sticker_creator/widgets/toast.dart` doesn't exist.

- [ ] **Step 2: Write `lib/widgets/toast.dart`**

```dart
import 'package:flutter/material.dart';

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        backgroundColor: const Color(0xFF16130F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: const Duration(milliseconds: 2200),
        margin: const EdgeInsets.only(left: 22, right: 22, bottom: 100),
      ),
    );
}
```

- [ ] **Step 3: Run the test**

Run: `fvm flutter test test/widgets/toast_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/toast.dart test/widgets/toast_test.dart
git commit -m "Add showToast: dark pill SnackBar matching the mockup's toast"
```

---

## Task 6: `CropScreen` (replaces `image_cropper`)

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/screens/crop_screen.dart`

**Interfaces:**
- Consumes: `PackDetailBloc` (via `context.read`, provided by whoever pushes this screen — Task 8 pushes it with `BlocProvider.value`), its `TrayIconSet(String croppedImagePath)` event.
- Produces: `CropScreen({required String sourcePath})`. Pops itself on cancel or after a successful crop.

- [ ] **Step 1: Swap the dependency**

In `pubspec.yaml`, remove:

```yaml
  image_cropper: ^12.2.1
```

Add (same `dependencies:` block):

```yaml
  crop_your_image: ^1.1.1
```

Run: `fvm flutter pub get`

- [ ] **Step 2: Write `lib/screens/crop_screen.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../blocs/pack_detail/pack_detail_bloc.dart';
import '../blocs/pack_detail/pack_detail_event.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    File(widget.sourcePath).readAsBytes().then((bytes) {
      if (mounted) setState(() => _imageBytes = bytes);
    });
  }

  Future<void> _onCropped(Uint8List croppedBytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final outputPath = p.join(
      dir.path,
      'stickers',
      '${DateTime.now().microsecondsSinceEpoch}_crop.png',
    );
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await File(outputPath).writeAsBytes(croppedBytes);
    if (!mounted) return;
    context.read<PackDetailBloc>().add(TrayIconSet(outputPath));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;
    return Scaffold(
      backgroundColor: const Color(0xFF100D0A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Crop tray icon',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Text('1:1 · 96×96', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: bytes == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Crop(
                        controller: _controller,
                        image: bytes,
                        aspectRatio: 1,
                        onCropped: _onCropped,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Tray icons are square. This crop is resized to 96×96 and saved as PNG.',
                style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B57),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: bytes == null ? null : () => _controller.crop(),
                      child: const Text('Use as tray icon'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify**

Run: `fvm flutter analyze`
Expected: clean (no references to `CropScreen` yet outside this file, so nothing else to break — Task 8 wires the push site).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/screens/crop_screen.dart
git commit -m "Add CropScreen (crop_your_image), replacing image_cropper's unthemeable native crop UI"
```

---

## Task 7: `PackListScreen` (Home) redesign

**Files:**
- Create: `lib/widgets/app_sheet.dart`
- Modify: `lib/widgets/pack_list_tile.dart`
- Modify: `lib/screens/pack_list_screen.dart`

**Interfaces:**
- Produces: `Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder)`, `Widget sheetDragHandle(BuildContext context)` — reused by Task 8/9's sheets.
- `PackListTile({required StickerPack pack, required VoidCallback onTap, required VoidCallback onMenu})` (replaces the old `onDelete` param — delete now lives behind the overflow sheet).

- [ ] **Step 1: Write `lib/widgets/app_sheet.dart`**

```dart
import 'package:flutter/material.dart';

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: builder(sheetContext),
    ),
  );
}

Widget sheetDragHandle(BuildContext context) {
  return Center(
    child: Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
```

- [ ] **Step 2: Redesign `lib/widgets/pack_list_tile.dart`**

Replace the full file:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/sticker_pack.dart';
import '../theme.dart';

class PackListTile extends StatelessWidget {
  const PackListTile({super.key, required this.pack, required this.onTap, required this.onMenu});

  final StickerPack pack;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final mini = pack.stickers.take(4).toList();
    final meta =
        '${pack.stickers.length} ${pack.stickers.length == 1 ? 'sticker' : 'stickers'}'
        '${pack.trayIconPath == null ? ' · no tray icon' : ''}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surf,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 76,
              height: 76,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.surf2,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.stick, width: 3),
              ),
              child: pack.trayIconPath != null
                  ? Image.file(File(pack.trayIconPath!), fit: BoxFit.cover)
                  : Center(
                      child: Text(
                        'no\ntray',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 9, color: colors.mut),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.tx),
                  ),
                  const SizedBox(height: 3),
                  Text(meta, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.mut)),
                  if (mini.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        for (final sticker in mini)
                          Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 4),
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: colors.surf2,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Image.file(File(sticker.filePath), fit: BoxFit.cover),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.more_vert), onPressed: onMenu),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Redesign `lib/screens/pack_list_screen.dart`**

Replace the full file:

```dart
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
                              state is PackListLoaded && state.packs.isNotEmpty
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
                  child: state is! PackListLoaded
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
                                      .then(
                                        (_) => context.read<PackListBloc>().add(const PackListLoadRequested()),
                                      ),
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
```

- [ ] **Step 4: Verify**

Run: `fvm flutter analyze`
Expected: clean.

- [ ] **Step 5: Manual verification**

Run: `fvm flutter run` on the connected device. Confirm: header shows "Stickerbox" + subtitle + dark-mode toggle; empty state shows the mascot illustration; creating a pack via the bottom sheet works; the per-pack "⋮" opens Rename/Delete and both work; toggling dark mode restyles the whole screen and survives an app restart.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/app_sheet.dart lib/widgets/pack_list_tile.dart lib/screens/pack_list_screen.dart
git commit -m "Redesign PackListScreen (Home): header, empty state, pack cards, create/rename/delete sheets"
```

---

## Task 8: `PackDetailScreen` redesign, part A — layout, tray/crop, grid, CTA, overflow

**Files:**
- Modify: `lib/widgets/sticker_grid_tile.dart`
- Modify: `lib/screens/pack_detail_screen.dart`

**Interfaces:**
- `StickerGridTile({required String filePath, required bool isAnimated, required VoidCallback onRemove})`.
- `PackDetailScreen` now provides `ImportBloc` at its own level (via `BlocProvider`, alongside the `PackDetailBloc` provided by its pusher) — Task 9 adds the listener that drives the processing sheet from it; Task 10 makes `ImportScreen` pop immediately after dispatching into this same bloc instance (passed down via `BlocProvider.value`, same pattern as `PackDetailBloc` already uses).

- [ ] **Step 1: Redesign `lib/widgets/sticker_grid_tile.dart`**

Replace the full file:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

class StickerGridTile extends StatelessWidget {
  const StickerGridTile({
    super.key,
    required this.filePath,
    required this.isAnimated,
    required this.onRemove,
  });

  final String filePath;
  final bool isAnimated;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.stick, width: 3),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: Image.file(File(filePath), fit: BoxFit.cover)),
          if (isAnimated)
            Positioned(
              left: 7,
              top: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xA8100D0A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'GIF',
                  style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          Positioned(
            right: 6,
            top: 6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(color: Color(0x99100D0A), shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Redesign `lib/screens/pack_detail_screen.dart`**

Replace the full file:

```dart
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

  Widget _bottomCta(BuildContext context, PackDetailLoaded state) {
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
    final n = state.pack.stickers.length;
    final noTray = state.pack.trayIconPath == null;
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

  // Placeholder wired up fully in Task 9 — kept here so this task compiles
  // and the button above has somewhere real to call.
  void _openWaConfirmSheet(BuildContext context, PackDetailLoaded state) {}

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ImportBloc(
        importRepository: ImportRepository(),
        stickerProcessor: context.read<StickerProcessor>(),
        thumbnailFetcher: LinkThumbnailFetcher(),
      ),
      child: BlocListener<PackDetailBloc, PackDetailState>(
        listenWhen: (previous, current) => previous is PackDetailLoaded && current is PackDetailNotFound,
        listener: (context, state) {
          Navigator.of(context).pop();
          showToast(context, 'Pack deleted');
        },
        child: BlocBuilder<PackDetailBloc, PackDetailState>(
          builder: (context, state) {
            final colors = Theme.of(context).extension<AppColors>()!;
            if (state is PackDetailNotFound) {
              return const Scaffold(body: Center(child: Text('Pack not found')));
            }
            if (state is! PackDetailLoaded) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final pack = state.pack;
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
```

Note: `Container(... clipBehavior...)` style widgets above use `File(...)` from `dart:io` — add the import at the top:

```dart
import 'dart:io';
```

- [ ] **Step 3: Verify**

Run: `fvm flutter analyze`
Expected: clean.

- [ ] **Step 4: Manual verification**

Run: `fvm flutter run`. Confirm: Detail header (back/name/dark-toggle/overflow) renders; tray card's "Set icon"/"Change" opens the image picker then `CropScreen`, and confirming there sets the tray icon; sticker grid renders with the new tile styling; bottom CTA shows the correct disabled+helper-text state below 3 stickers or with no tray icon, and switches to the enabled "Add to WhatsApp" style once eligible (tapping it does nothing yet — Task 9); overflow menu's Rename/Delete both work and Delete pops back to Home with a toast.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/sticker_grid_tile.dart lib/screens/pack_detail_screen.dart
git commit -m "Redesign PackDetailScreen: header, tray/crop card, sticker grid, bottom CTA, overflow menu"
```

---

## Task 9: `PackDetailScreen` redesign, part B — processing sheet, WhatsApp sheets/dialog

**Files:**
- Modify: `lib/screens/pack_detail_screen.dart`

**Interfaces:**
- Consumes: `ImportBloc`'s states (`ImportProcessing(current, total)`, `ImportReady(paths, type)`, `ImportFailure(message)`) via a `BlocListener` added at the same level as the one from Task 8.
- Replaces the `_openWaConfirmSheet` stub from Task 8 with a real implementation.

- [ ] **Step 1: Add the processing-sheet listener and WhatsApp sheets/dialog**

In `lib/screens/pack_detail_screen.dart`, add a field to `_PackDetailScreenState`:

```dart
  bool _procSheetOpen = false;
```

Replace the `_openWaConfirmSheet` stub with:

```dart
  void _openProcessingSheetIfNeeded(BuildContext context) {
    if (_procSheetOpen) return;
    _procSheetOpen = true;
    showAppSheet<void>(context, (sheetContext) => _ProcessingSheetContent(closeSelf: () {
          if (Navigator.of(sheetContext).canPop()) Navigator.of(sheetContext).pop();
        })).then((_) => _procSheetOpen = false);
  }

  void _handleImportState(BuildContext context, ImportState state) {
    if (state is ImportProcessing || state is ImportFailure) {
      _openProcessingSheetIfNeeded(context);
    } else if (state is ImportReady) {
      context.read<PackDetailBloc>().add(StickersAdded(state.processedFilePaths, state.type));
      Future.delayed(const Duration(milliseconds: 950), () {
        if (_procSheetOpen && context.mounted) Navigator.of(context).pop();
        if (context.mounted) {
          showToast(
            context,
            state.processedFilePaths.length > 1
                ? '${state.processedFilePaths.length} stickers added'
                : 'Sticker added',
          );
        }
      });
    }
  }

  Future<void> _openWaConfirmSheet(BuildContext context, PackDetailLoaded state) async {
    final handoff = context.read<WhatsAppHandoff>();
    final pack = state.pack;
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
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: colors.tx),
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
                  if (!await handoff.isWhatsAppInstalled()) {
                    if (context.mounted) _showWaMissingDialog(context);
                    return;
                  }
                  await handoff.addPack(pack);
                  if (context.mounted) _openWaSuccessSheet(context, pack.name);
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
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: colors.tx),
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

  void _showWaMissingDialog(BuildContext context) {
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
                  "WhatsApp isn't installed",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: colors.tx),
                ),
                const SizedBox(height: 8),
                Text(
                  'This sticker pack can be added when WhatsApp is installed on your device.',
                  style: TextStyle(fontSize: 14, color: colors.mut),
                ),
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
```

Remove the `_openWaConfirmSheet` stub method left over from Task 8.

Add `_ProcessingSheetContent` as a private widget at the bottom of the file (below the closing brace of `_PackDetailScreenState`):

```dart

class _ProcessingSheetContent extends StatelessWidget {
  const _ProcessingSheetContent({required this.closeSelf});

  final VoidCallback closeSelf;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ImportBloc, ImportState>(
      builder: (context, state) {
        final colors = Theme.of(context).extension<AppColors>()!;
        final busy = state is ImportProcessing;
        final failed = state is ImportFailure;
        final total = state is ImportProcessing ? state.total : null;
        final current = state is ImportProcessing ? state.current : null;
        final title = failed
            ? "Couldn't add sticker"
            : total != null && total > 1
                ? 'Adding stickers'
                : 'Preparing your sticker…';
        final subtitle = failed
            ? (state as ImportFailure).message
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
```

Now wire the listener into `build()`. Wrap the existing `BlocListener<PackDetailBloc, ...>` in a `MultiBlocListener` alongside a new `BlocListener<ImportBloc, ImportState>`:

```dart
    return BlocProvider(
      create: (context) => ImportBloc(
        importRepository: ImportRepository(),
        stickerProcessor: context.read<StickerProcessor>(),
        thumbnailFetcher: LinkThumbnailFetcher(),
      ),
      child: MultiBlocListener(
        listeners: [
          BlocListener<PackDetailBloc, PackDetailState>(
            listenWhen: (previous, current) => previous is PackDetailLoaded && current is PackDetailNotFound,
            listener: (context, state) {
              Navigator.of(context).pop();
              showToast(context, 'Pack deleted');
            },
          ),
          BlocListener<ImportBloc, ImportState>(listener: _handleImportState),
        ],
        child: BlocBuilder<PackDetailBloc, PackDetailState>(
```

...and close the extra `MultiBlocListener` widget instead of the old `BlocListener` at the end of `build()` (one extra closing parenthesis where the old single `BlocListener(...)` used to close).

Add the missing import at the top of the file:

```dart
import 'dart:io';

import '../blocs/import/import_event.dart';
import '../blocs/import/import_state.dart';
```

(`import_bloc.dart` already imports `ImportBloc`; `ImportEvent`/`ImportState` need their own imports since `_handleImportState` and `_ProcessingSheetContent` reference `ImportProcessing`/`ImportFailure`/`ImportReady` directly.)

- [ ] **Step 2: Verify**

Run: `fvm flutter analyze`
Expected: clean.

- [ ] **Step 3: Manual verification**

Run: `fvm flutter run`. Confirm: adding stickers (from Task 10's still-old `ImportScreen` for now, or by temporarily testing after Task 10) shows the processing sheet with a live progress bar for multi-image picks, and a spinner-less single-item message for GIF/link; a forced failure (e.g. airplane mode during a link import) shows the failure state with Cancel; tapping "Add to WhatsApp" when eligible opens the confirm sheet, and completing it shows the success sheet; if WhatsApp isn't installed on the test device, the centered "WhatsApp isn't installed" dialog appears instead.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/pack_detail_screen.dart
git commit -m "Add PackDetailScreen's processing sheet with live progress and the WhatsApp confirm/success/missing UI"
```

---

## Task 10: `ImportScreen` redesign — segmented tabs, device/link tabs, pop-immediately

**Files:**
- Modify: `lib/screens/import_screen.dart`

**Interfaces:**
- Consumes: the `ImportBloc` and `PackDetailBloc` now provided above it by `PackDetailScreen` (Task 8's `_openImportScreen`), via `BlocProvider.value`.
- No longer dispatches `StickersAdded` itself (that moved to `PackDetailScreen`'s `ImportBloc` listener in Task 9) and no longer waits for `ImportReady` before popping.

- [ ] **Step 1: Replace `lib/screens/import_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/import/import_bloc.dart';
import '../blocs/import/import_event.dart';
import '../blocs/import/import_state.dart';
import '../repositories/link_thumbnail_fetcher.dart';
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
          leading: Text('GIF', style: TextStyle(fontWeight: FontWeight.w700, color: colors.tx)),
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
    return BlocBuilder<ImportBloc, ImportState>(
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
                SizedBox(
                  width: 78,
                  height: 54,
                  child: OutlinedButton(
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _urlController.text = data!.text!;
                        setState(() {});
                      }
                    },
                    child: const Text('Paste'),
                  ),
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
            if (state is ImportProcessing) ...[
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
            if (state is ImportThumbnailPreview) ...[
              const SizedBox(height: 22),
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.file(File(state.localPreviewPath), width: double.infinity, fit: BoxFit.cover),
              ),
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
                      onPressed: () => _dispatchAndClose(const LinkThumbnailConfirmed()),
                      child: const Text('Add Sticker'),
                    ),
                  ),
                ],
              ),
            ],
            if (state is ImportFailure) ...[
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: colors.surf, borderRadius: BorderRadius.circular(26)),
                child: Column(
                  children: [
                    Text(
                      state.message,
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
```

Add the two missing imports at the top of the file:

```dart
import 'dart:io';

import 'package:flutter/services.dart';
```

Note the deliberate behavior changes from the old file: `_pendingType` is gone (the bloc now reports `type` on `ImportReady`, per Task 4); `PickStaticImagesRequested`/`PickGifRequested`/`LinkThumbnailConfirmed` all pop the screen immediately via `_dispatchAndClose`/`_openImportScreen`'s route rather than waiting for a `BlocConsumer` to observe `ImportReady`; `LinkUrlSubmitted` (fetching a preview) does **not** pop — the user needs to see the fetched preview and tap "Add Sticker" before this screen closes.

- [ ] **Step 2: Verify**

Run: `fvm flutter analyze`
Expected: clean — this also confirms `import_repository.dart`'s now-unused `LinkThumbnailFetcher` import removal isn't needed (it's still used elsewhere) and that removing `image_picker`/`image_cropper` imports from this file doesn't break anything (this screen no longer imports either).

- [ ] **Step 3: Run the full suite**

Run: `fvm flutter analyze && fvm flutter test`
Expected: clean, all pass.

- [ ] **Step 4: Manual verification (full golden path)**

Run: `fvm flutter run` on the connected device and walk the whole flow end to end:
1. Home: create a pack via the sheet.
2. Detail: tap "Add Stickers" → Import screen opens with the segmented tabs.
3. Device tab: pick 2+ images → Import screen closes immediately → Detail's processing sheet shows live "N of M" progress → sticker grid updates.
4. Device tab: pick a GIF → same flow, single-item copy, GIF badge shows on the resulting tile.
5. Link tab: paste/type a supported URL → preview appears → "Add Sticker" → same processing-sheet flow.
6. Link tab: submit an unsupported URL → real `LinkThumbnailException` message shows in the error state, "Try Again" retries.
7. Set a tray icon via the crop flow; once ≥3 stickers and a tray icon exist, the bottom CTA switches to enabled "Add to WhatsApp" and the confirm→success (or confirm→missing-dialog, on a device without WhatsApp) flow completes.
8. Toggle dark mode from either Home or Detail and confirm it applies everywhere and survives an app restart.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/import_screen.dart
git commit -m "Redesign ImportScreen: segmented tabs, device/link tab UI, pop-immediately-on-dispatch"
```

---

## Self-Review Notes

- **Spec coverage:** dark mode (Task 1), app icon/logo (Task 2), rename/delete (Tasks 3, 7, 8), processing sheet with live progress (Tasks 4, 9), toast (Task 5), custom `CropScreen` (Task 6), Home redesign (Task 7), Detail redesign incl. the `ImportBloc` lifetime move (Tasks 8–9), Import redesign incl. pop-immediately (Task 10), "Stickerbox" rename (Task 1's `main.dart`, Task 7's header) — every in-scope spec item maps to a task above.
- **Root-cause fix, not a patch:** `ImportReady` gaining a `type` field (Task 4) replaces `ImportScreen`'s old `_pendingType` instance-field tracking, which would have silently broken once Import started popping before `ImportReady` arrived (Task 10) — the type now travels with the bloc's own state instead of living in a widget that no longer exists when it's needed.
- **Type consistency check:** `StickerGridTile(filePath, isAnimated, onRemove)` (Task 8) matches its one call site in the same task. `PackListTile(pack, onTap, onMenu)` (Task 7) matches its one call site in the same task. `showAppSheet<T>(context, WidgetBuilder)` (Task 7) is used with matching signatures in Tasks 7, 8, 9. `ImportReady(paths, type)` (Task 4) matches every construction site in `import_bloc.dart` (same task) and every consumer (`PackDetailScreen._handleImportState` in Task 9).
