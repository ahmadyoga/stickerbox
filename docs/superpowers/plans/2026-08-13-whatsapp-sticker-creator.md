# WhatsApp Sticker Creator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter (Android + iOS) app that turns direct image picks and TikTok/Instagram/Pinterest links into WhatsApp sticker packs and hands them off to WhatsApp.

**Architecture:** Layered `UI → Bloc → Repository → data source`, using `flutter_bloc`. Packs/stickers metadata persist in Hive with hand-written `TypeAdapter`s (no codegen — the schema is 2 small, stable classes); sticker image bytes live as files on disk. No JSON manifest, no SQL.

**Tech Stack:** `flutter_bloc`, `equatable`, `hive`/`hive_flutter`, `path_provider`, `image_picker`, `file_picker`, `image_cropper`, `flutter_image_compress`, `image` (pure-Dart, for animated WebP + tray icon), `http`, `html`, `receive_sharing_intent`; dev: `bloc_test`, `mocktail`.

## Global Constraints

- Static stickers: WebP, ≤100KB, 512×512.
- Animated stickers: animated WebP, ≤500KB, 512×512, GIF source only (no video import — `ffmpeg_kit_flutter` is retired; see spec).
- Tray icon: PNG, 96×96.
- Packs require 3–30 stickers before "Add to WhatsApp" is enabled.
- No emoji tagging (v1).
- Link import (share sheet + paste URL) only ever produces a static sticker source (a scraped `og:image` thumbnail), never animated.
- No new IDs library — generate ids as `'${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}'` (one line, no `uuid` dependency; collision risk is irrelevant for single-user, non-concurrent local creation).
- Full spec: `docs/superpowers/specs/2026-08-13-whatsapp-sticker-creator-design.md`.

---

## Task 1: Project setup — dependencies, folders, Hive init

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/hive/hive_setup.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Produces: `Future<void> setUpHive()` — registers adapters (added in Task 2) and opens the `packs` Hive box. Called once from `main()` before `runApp`.

- [ ] **Step 1: Add dependencies**

Run:
```bash
flutter pub add flutter_bloc equatable hive hive_flutter path_provider image_picker file_picker image_cropper flutter_image_compress image http html receive_sharing_intent
flutter pub add --dev bloc_test mocktail
```

- [ ] **Step 2: Create the lib folder scaffold**

Run:
```bash
mkdir -p lib/hive lib/models lib/repositories lib/blocs/pack_list lib/blocs/pack_detail lib/blocs/import lib/screens lib/widgets
mkdir -p test/repositories test/blocs
```

- [ ] **Step 3: Write `lib/hive/hive_setup.dart`**

```dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/sticker.dart';
import '../models/sticker_pack.dart';

const packsBoxName = 'packs';

Future<Box<StickerPack>> setUpHive() async {
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(StickerPackAdapter());
  }
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(StickerAdapter());
  }
  return Hive.openBox<StickerPack>(packsBoxName);
}
```

This references `StickerPackAdapter`/`StickerAdapter`, written in Task 2 — this task will not compile until Task 2 lands. That's expected; run `flutter analyze` after Task 2 instead of after this step.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/hive
git commit -m "Add dependencies and Hive setup scaffold"
```

---

## Task 2: Sticker & StickerPack models + PackRepository

**Files:**
- Create: `lib/models/sticker.dart`
- Create: `lib/models/sticker_pack.dart`
- Create: `lib/repositories/pack_repository.dart`
- Test: `test/repositories/pack_repository_test.dart`

**Interfaces:**
- Produces:
  - `enum StickerType { static_, animated }`
  - `class Sticker { final String id; final String filePath; final StickerType type; }`
  - `class StickerPack { final String id; String name; String publisherName; String? trayIconPath; final List<Sticker> stickers; }`
  - `class PackRepository { List<StickerPack> getAllPacks(); StickerPack? getPack(String id); Future<void> savePack(StickerPack pack); Future<void> deletePack(String id); }`
- Consumes: `setUpHive()` from Task 1 in the test to get a real (temp-dir) `Box<StickerPack>`.

- [ ] **Step 1: Write `lib/models/sticker.dart`**

```dart
import 'package:hive/hive.dart';

enum StickerType { static_, animated }

class Sticker {
  Sticker({required this.id, required this.filePath, required this.type});

  final String id;
  final String filePath;
  final StickerType type;
}

class StickerAdapter extends TypeAdapter<Sticker> {
  @override
  final int typeId = 1;

  @override
  Sticker read(BinaryReader reader) {
    final id = reader.readString();
    final filePath = reader.readString();
    final type = StickerType.values[reader.readByte()];
    return Sticker(id: id, filePath: filePath, type: type);
  }

  @override
  void write(BinaryWriter writer, Sticker obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.filePath);
    writer.writeByte(obj.type.index);
  }
}
```

- [ ] **Step 2: Write `lib/models/sticker_pack.dart`**

```dart
import 'package:hive/hive.dart';

import 'sticker.dart';

class StickerPack {
  StickerPack({
    required this.id,
    required this.name,
    required this.publisherName,
    this.trayIconPath,
    List<Sticker>? stickers,
  }) : stickers = stickers ?? [];

  final String id;
  String name;
  String publisherName;
  String? trayIconPath;
  final List<Sticker> stickers;
}

class StickerPackAdapter extends TypeAdapter<StickerPack> {
  @override
  final int typeId = 0;

  @override
  StickerPack read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final publisherName = reader.readString();
    final hasTrayIcon = reader.readBool();
    final trayIconPath = hasTrayIcon ? reader.readString() : null;
    final stickerCount = reader.readInt();
    final stickers = <Sticker>[
      for (var i = 0; i < stickerCount; i++) reader.read() as Sticker,
    ];
    return StickerPack(
      id: id,
      name: name,
      publisherName: publisherName,
      trayIconPath: trayIconPath,
      stickers: stickers,
    );
  }

  @override
  void write(BinaryWriter writer, StickerPack obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeString(obj.publisherName);
    writer.writeBool(obj.trayIconPath != null);
    if (obj.trayIconPath != null) writer.writeString(obj.trayIconPath!);
    writer.writeInt(obj.stickers.length);
    for (final sticker in obj.stickers) {
      writer.write(sticker);
    }
  }
}
```

- [ ] **Step 3: Write `lib/repositories/pack_repository.dart`**

```dart
import 'package:hive/hive.dart';

import '../models/sticker_pack.dart';

class PackRepository {
  PackRepository(this._box);

  final Box<StickerPack> _box;

  List<StickerPack> getAllPacks() => _box.values.toList();

  StickerPack? getPack(String id) => _box.get(id);

  Future<void> savePack(StickerPack pack) => _box.put(pack.id, pack);

  Future<void> deletePack(String id) => _box.delete(id);
}
```

- [ ] **Step 4: Write the failing test — round-trip through a real Hive box**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sticker_creator/models/sticker.dart';
import 'package:sticker_creator/models/sticker_pack.dart';
import 'package:sticker_creator/repositories/pack_repository.dart';

void main() {
  late Box<StickerPack> box;
  late PackRepository repository;

  setUp(() async {
    Hive.init('.dart_tool/test_hive');
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(StickerPackAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(StickerAdapter());
    box = await Hive.openBox<StickerPack>('test_packs_${DateTime.now().microsecondsSinceEpoch}');
    repository = PackRepository(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  test('savePack then getPack round-trips all fields including stickers', () async {
    final pack = StickerPack(
      id: 'pack-1',
      name: 'My Pack',
      publisherName: 'Me',
      trayIconPath: '/tmp/tray.png',
      stickers: [
        Sticker(id: 's1', filePath: '/tmp/s1.webp', type: StickerType.static_),
        Sticker(id: 's2', filePath: '/tmp/s2.webp', type: StickerType.animated),
      ],
    );

    await repository.savePack(pack);
    final loaded = repository.getPack('pack-1')!;

    expect(loaded.id, 'pack-1');
    expect(loaded.name, 'My Pack');
    expect(loaded.publisherName, 'Me');
    expect(loaded.trayIconPath, '/tmp/tray.png');
    expect(loaded.stickers, hasLength(2));
    expect(loaded.stickers[0].id, 's1');
    expect(loaded.stickers[0].type, StickerType.static_);
    expect(loaded.stickers[1].type, StickerType.animated);
  });

  test('getAllPacks returns every saved pack; deletePack removes one', () async {
    await repository.savePack(StickerPack(id: 'a', name: 'A', publisherName: 'Me'));
    await repository.savePack(StickerPack(id: 'b', name: 'B', publisherName: 'Me'));

    expect(repository.getAllPacks(), hasLength(2));

    await repository.deletePack('a');

    expect(repository.getAllPacks(), hasLength(1));
    expect(repository.getPack('a'), isNull);
  });
}
```

- [ ] **Step 5: Run the tests**

Run: `flutter test test/repositories/pack_repository_test.dart`
Expected: PASS. (`path_provider_platform_interface`/`plugin_platform_interface` are transitive deps already pulled in by `path_provider`/`hive_flutter`; if the import fails, run `flutter pub get` first — no new dependency needed.)

- [ ] **Step 6: Commit**

```bash
git add lib/models lib/repositories/pack_repository.dart test/repositories/pack_repository_test.dart
git commit -m "Add Sticker/StickerPack Hive models and PackRepository"
```

---

## Task 3: Compression decision logic (pure functions)

**Files:**
- Create: `lib/repositories/compression.dart`
- Test: `test/repositories/compression_test.dart`

**Interfaces:**
- Produces:
  - `class StickerTooLargeException implements Exception { final String message; }`
  - `int? nextStaticQuality({required int currentQuality, required int currentSizeBytes, required int targetBytes, int floor = 10, int step = 15})`
  - `class AnimatedEncodeAttempt { final int colorCount; final int frameStep; const AnimatedEncodeAttempt({required this.colorCount, required this.frameStep}); }`
  - `AnimatedEncodeAttempt? nextAnimatedAttempt({required AnimatedEncodeAttempt current, required int currentSizeBytes, required int targetBytes, int colorFloor = 32, int colorStep = 32, int maxFrameStep = 4})`
- Consumed by: `StickerProcessor` (Tasks 4–5).

This is the seam the spec calls out for testing — the loop *decision* logic, kept free of any actual image encoding so it runs in milliseconds with no fixtures.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_creator/repositories/compression.dart';

void main() {
  group('nextStaticQuality', () {
    test('returns null when already under target', () {
      final result = nextStaticQuality(
        currentQuality: 90,
        currentSizeBytes: 50 * 1024,
        targetBytes: 100 * 1024,
      );
      expect(result, isNull);
    });

    test('steps quality down when over target', () {
      final result = nextStaticQuality(
        currentQuality: 90,
        currentSizeBytes: 150 * 1024,
        targetBytes: 100 * 1024,
        step: 15,
      );
      expect(result, 75);
    });

    test('throws once quality would drop below floor', () {
      expect(
        () => nextStaticQuality(
          currentQuality: 20,
          currentSizeBytes: 150 * 1024,
          targetBytes: 100 * 1024,
          floor: 10,
          step: 15,
        ),
        throwsA(isA<StickerTooLargeException>()),
      );
    });
  });

  group('nextAnimatedAttempt', () {
    const start = AnimatedEncodeAttempt(colorCount: 256, frameStep: 1);

    test('returns null when already under target', () {
      final result = nextAnimatedAttempt(
        current: start,
        currentSizeBytes: 100 * 1024,
        targetBytes: 500 * 1024,
      );
      expect(result, isNull);
    });

    test('reduces color count first when over target', () {
      final result = nextAnimatedAttempt(
        current: start,
        currentSizeBytes: 600 * 1024,
        targetBytes: 500 * 1024,
        colorStep: 32,
        colorFloor: 32,
      );
      expect(result!.colorCount, 224);
      expect(result.frameStep, 1);
    });

    test('increases frame step once color count is at the floor', () {
      const atFloor = AnimatedEncodeAttempt(colorCount: 32, frameStep: 1);
      final result = nextAnimatedAttempt(
        current: atFloor,
        currentSizeBytes: 600 * 1024,
        targetBytes: 500 * 1024,
        colorFloor: 32,
        maxFrameStep: 4,
      );
      expect(result!.colorCount, 32);
      expect(result.frameStep, 2);
    });

    test('throws once both color count and frame step are exhausted', () {
      const exhausted = AnimatedEncodeAttempt(colorCount: 32, frameStep: 4);
      expect(
        () => nextAnimatedAttempt(
          current: exhausted,
          currentSizeBytes: 600 * 1024,
          targetBytes: 500 * 1024,
          colorFloor: 32,
          maxFrameStep: 4,
        ),
        throwsA(isA<StickerTooLargeException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/repositories/compression_test.dart`
Expected: FAIL (`compression.dart` doesn't exist yet)

- [ ] **Step 3: Write `lib/repositories/compression.dart`**

```dart
class StickerTooLargeException implements Exception {
  StickerTooLargeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Returns the next WebP quality to try for a lossy static encode, or null
/// once [currentSizeBytes] is already within [targetBytes].
int? nextStaticQuality({
  required int currentQuality,
  required int currentSizeBytes,
  required int targetBytes,
  int floor = 10,
  int step = 15,
}) {
  if (currentSizeBytes <= targetBytes) return null;
  final next = currentQuality - step;
  if (next < floor) {
    throw StickerTooLargeException(
      'Image too complex to fit under ${targetBytes ~/ 1024}KB',
    );
  }
  return next;
}

/// Parameters for one lossless animated-encode attempt: how many colors to
/// quantize down to, and how many source frames to skip between kept frames.
class AnimatedEncodeAttempt {
  const AnimatedEncodeAttempt({required this.colorCount, required this.frameStep});

  final int colorCount;
  final int frameStep;
}

/// Returns the next attempt to try for a lossless animated encode, or null
/// once [currentSizeBytes] is already within [targetBytes]. Reduces color
/// count first (cheaper to visual quality), then falls back to dropping
/// frames once color count hits [colorFloor].
AnimatedEncodeAttempt? nextAnimatedAttempt({
  required AnimatedEncodeAttempt current,
  required int currentSizeBytes,
  required int targetBytes,
  int colorFloor = 32,
  int colorStep = 32,
  int maxFrameStep = 4,
}) {
  if (currentSizeBytes <= targetBytes) return null;
  if (current.colorCount - colorStep >= colorFloor) {
    return AnimatedEncodeAttempt(
      colorCount: current.colorCount - colorStep,
      frameStep: current.frameStep,
    );
  }
  if (current.frameStep < maxFrameStep) {
    return AnimatedEncodeAttempt(
      colorCount: current.colorCount,
      frameStep: current.frameStep + 1,
    );
  }
  throw StickerTooLargeException(
    'GIF too complex to fit under ${targetBytes ~/ 1024}KB',
  );
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/repositories/compression_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/compression.dart test/repositories/compression_test.dart
git commit -m "Add pure compression-loop decision logic for sticker encoding"
```

---

## Task 4: StickerProcessor — static encode

**Files:**
- Create: `lib/repositories/sticker_processor.dart`
- Test: `test/repositories/sticker_processor_static_test.dart`
- Create fixture: `test/fixtures/sample.jpg` (any real JPEG ≥512×512, e.g. a photo — add via `git add -f` since large binary fixtures aren't code but are needed for this test)

**Interfaces:**
- Consumes: nothing new (uses `flutter_image_compress` directly, plus `nextStaticQuality` from Task 3).
- Produces: `class StickerProcessor { Future<void> encodeStatic(String inputPath, String outputPath); }` (methods `encodeAnimatedGif` and `encodeTrayIcon` added in Tasks 5–6 on the same class).

- [ ] **Step 1: Add a real JPEG fixture**

Place any real JPEG at `test/fixtures/sample.jpg` (≥512×512, a few hundred KB — a photo works well since it stresses the compression loop). This can be any non-sensitive stock/sample photo.

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sticker_creator/repositories/sticker_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encodeStatic produces a WebP file under 100KB', () async {
    final processor = StickerProcessor();
    final outputPath = p.join(
      Directory.systemTemp.path,
      'sticker_test_${DateTime.now().microsecondsSinceEpoch}.webp',
    );

    await processor.encodeStatic('test/fixtures/sample.jpg', outputPath);

    final output = File(outputPath);
    expect(output.existsSync(), isTrue);
    expect(output.lengthSync(), lessThanOrEqualTo(100 * 1024));

    output.deleteSync();
  });
}
```

`path` is a transitive dependency already present (pulled in by `flutter_test`); if the import fails, run `flutter pub add path`.

Note: `flutter_image_compress` uses platform channels, so this test must run with `flutter test` (which provides the test binding/mocked platform channels via the plugin's own test support) rather than plain `dart test`. If `compressWithFile` returns null in the test environment because there's no real platform channel implementation, switch this test to `flutter test integration_test/` (device/emulator required) instead — call this out to the user if it happens rather than working around it with a fake.

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/repositories/sticker_processor_static_test.dart`
Expected: FAIL (`sticker_processor.dart` doesn't exist yet)

- [ ] **Step 4: Write `lib/repositories/sticker_processor.dart`**

```dart
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'compression.dart';

class StickerProcessor {
  static const staticTargetBytes = 100 * 1024;
  static const stickerDimension = 512;

  /// Encodes a single image file into a WhatsApp-compliant static WebP
  /// sticker, writing the result to [outputPath].
  Future<void> encodeStatic(String inputPath, String outputPath) async {
    var quality = 90;
    while (true) {
      final bytes = await FlutterImageCompress.compressWithFile(
        inputPath,
        format: CompressFormat.webp,
        minWidth: stickerDimension,
        minHeight: stickerDimension,
        quality: quality,
      );
      if (bytes == null) {
        throw StickerTooLargeException('Failed to encode sticker image');
      }
      final next = nextStaticQuality(
        currentQuality: quality,
        currentSizeBytes: bytes.length,
        targetBytes: staticTargetBytes,
      );
      if (next == null) {
        await File(outputPath).writeAsBytes(bytes);
        return;
      }
      quality = next;
    }
  }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/repositories/sticker_processor_static_test.dart`
Expected: PASS. If `compressWithFile` isn't mockable under plain `flutter test`, follow the note in Step 2 rather than skipping verification.

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/sticker_processor.dart test/repositories/sticker_processor_static_test.dart test/fixtures/sample.jpg
git commit -m "Add StickerProcessor.encodeStatic (crop-to-512, WebP, size-budget loop)"
```

---

## Task 5: StickerProcessor — animated GIF encode

**Files:**
- Modify: `lib/repositories/sticker_processor.dart`
- Test: `test/repositories/sticker_processor_animated_test.dart`
- Create fixture: `test/fixtures/sample.gif` (any small real animated GIF, a few frames)

**Interfaces:**
- Consumes: `AnimatedEncodeAttempt`, `nextAnimatedAttempt` (Task 3).
- Produces: adds `Future<void> encodeAnimatedGif(String inputPath, String outputPath)` to `StickerProcessor`.

- [ ] **Step 1: Add a real GIF fixture**

Place a small real animated GIF (a handful of frames, any subject) at `test/fixtures/sample.gif`.

- [ ] **Step 2: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sticker_creator/repositories/sticker_processor.dart';

void main() {
  test('encodeAnimatedGif produces an animated WebP file under 500KB', () async {
    final processor = StickerProcessor();
    final outputPath = p.join(
      Directory.systemTemp.path,
      'sticker_animated_test_${DateTime.now().microsecondsSinceEpoch}.webp',
    );

    await processor.encodeAnimatedGif('test/fixtures/sample.gif', outputPath);

    final output = File(outputPath);
    expect(output.existsSync(), isTrue);
    expect(output.lengthSync(), lessThanOrEqualTo(500 * 1024));

    output.deleteSync();
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/repositories/sticker_processor_animated_test.dart`
Expected: FAIL (`encodeAnimatedGif` doesn't exist yet)

- [ ] **Step 4: Add `encodeAnimatedGif` to `lib/repositories/sticker_processor.dart`**

```dart
import 'package:image/image.dart' as img;
```
(add to the existing import block)

```dart
  static const animatedTargetBytes = 500 * 1024;
  static const maxAnimatedFrames = 24; // ~3s at 8fps, well under WhatsApp's cap

  /// Encodes a GIF file into a WhatsApp-compliant animated WebP sticker,
  /// writing the result to [outputPath].
  Future<void> encodeAnimatedGif(String inputPath, String outputPath) async {
    final decoded = img.decodeGif(await File(inputPath).readAsBytes());
    if (decoded == null || decoded.frames.isEmpty) {
      throw StickerTooLargeException('Could not decode GIF');
    }
    final sourceFrames = decoded.frames;

    var attempt = const AnimatedEncodeAttempt(colorCount: 256, frameStep: 1);
    while (true) {
      img.Image? animated;
      var added = 0;
      for (var i = 0; i < sourceFrames.length && added < maxAnimatedFrames; i += attempt.frameStep) {
        var frame = img.copyResize(
          sourceFrames[i],
          width: stickerDimension,
          height: stickerDimension,
        );
        frame = img.quantize(frame, numberOfColors: attempt.colorCount);
        if (animated == null) {
          animated = frame;
        } else {
          animated.addFrame(frame);
        }
        added++;
      }
      if (animated == null) {
        throw StickerTooLargeException('GIF has no usable frames');
      }
      final bytes = img.WebPEncoder().encode(animated);
      final next = nextAnimatedAttempt(
        current: attempt,
        currentSizeBytes: bytes.length,
        targetBytes: animatedTargetBytes,
      );
      if (next == null) {
        await File(outputPath).writeAsBytes(bytes);
        return;
      }
      attempt = next;
    }
  }
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/repositories/sticker_processor_animated_test.dart`
Expected: PASS. If any `image` package method name here doesn't match the installed version exactly (API surface can shift between majors), fix the call site against the installed version's actual signature — the intent (decode GIF frames → resize → quantize → build multi-frame Image via `addFrame` → `WebPEncoder().encode`) is what must be preserved, not the exact method names.

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/sticker_processor.dart test/repositories/sticker_processor_animated_test.dart test/fixtures/sample.gif
git commit -m "Add StickerProcessor.encodeAnimatedGif (pure-Dart animated WebP encode)"
```

---

## Task 6: StickerProcessor — tray icon encode

**Files:**
- Modify: `lib/repositories/sticker_processor.dart`
- Test: `test/repositories/sticker_processor_tray_test.dart`

**Interfaces:**
- Produces: adds `Future<void> encodeTrayIcon(String inputPath, String outputPath)` to `StickerProcessor`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sticker_creator/repositories/sticker_processor.dart';

void main() {
  test('encodeTrayIcon produces a 96x96 PNG', () async {
    final processor = StickerProcessor();
    final outputPath = p.join(
      Directory.systemTemp.path,
      'tray_test_${DateTime.now().microsecondsSinceEpoch}.png',
    );

    await processor.encodeTrayIcon('test/fixtures/sample.jpg', outputPath);

    final bytes = await File(outputPath).readAsBytes();
    final decoded = img.decodePng(bytes)!;
    expect(decoded.width, 96);
    expect(decoded.height, 96);

    File(outputPath).deleteSync();
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/repositories/sticker_processor_tray_test.dart`
Expected: FAIL (`encodeTrayIcon` doesn't exist yet)

- [ ] **Step 3: Add `encodeTrayIcon` to `lib/repositories/sticker_processor.dart`**

```dart
  static const trayDimension = 96;

  /// Resizes an image file into a 96x96 PNG tray icon.
  Future<void> encodeTrayIcon(String inputPath, String outputPath) async {
    final source = img.decodeImage(await File(inputPath).readAsBytes());
    if (source == null) {
      throw StickerTooLargeException('Could not decode tray icon image');
    }
    final resized = img.copyResize(source, width: trayDimension, height: trayDimension);
    await File(outputPath).writeAsBytes(img.encodePng(resized));
  }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/repositories/sticker_processor_tray_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/sticker_processor.dart test/repositories/sticker_processor_tray_test.dart
git commit -m "Add StickerProcessor.encodeTrayIcon"
```

---

## Task 7: ImportRepository — direct picks

**Files:**
- Create: `lib/repositories/import_repository.dart`
- Test: `test/repositories/import_repository_test.dart`

**Interfaces:**
- Produces: `class ImportRepository { Future<List<String>> pickStaticImages(); Future<String?> pickGifFile(); }` (constructor takes optional `ImagePicker`/`FilePicker` for test injection; `fetchLinkThumbnail`/`getSharedUrlStream` added in Tasks 8–9 on the same class).
- Consumes: nothing new.

- [ ] **Step 1: Write the failing test (mocking `ImagePicker`)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sticker_creator/repositories/import_repository.dart';

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  late MockImagePicker imagePicker;
  late ImportRepository repository;

  setUp(() {
    imagePicker = MockImagePicker();
    repository = ImportRepository(imagePicker: imagePicker);
  });

  test('pickStaticImages returns the picked file paths', () async {
    when(() => imagePicker.pickMultiImage()).thenAnswer(
      (_) async => [XFile('/tmp/a.jpg'), XFile('/tmp/b.jpg')],
    );

    final paths = await repository.pickStaticImages();

    expect(paths, ['/tmp/a.jpg', '/tmp/b.jpg']);
  });

  test('pickStaticImages returns an empty list when nothing picked', () async {
    when(() => imagePicker.pickMultiImage()).thenAnswer((_) async => []);

    final paths = await repository.pickStaticImages();

    expect(paths, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/repositories/import_repository_test.dart`
Expected: FAIL (`import_repository.dart` doesn't exist yet)

- [ ] **Step 3: Write `lib/repositories/import_repository.dart`**

```dart
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class ImportRepository {
  ImportRepository({ImagePicker? imagePicker})
      : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<List<String>> pickStaticImages() async {
    final files = await _imagePicker.pickMultiImage();
    return files.map((f) => f.path).toList();
  }

  Future<String?> pickGifFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
    );
    return result?.files.single.path;
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/repositories/import_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/import_repository.dart test/repositories/import_repository_test.dart
git commit -m "Add ImportRepository direct-pick methods"
```

---

## Task 8: Link thumbnail scraping

**Files:**
- Create: `lib/repositories/link_thumbnail_fetcher.dart`
- Test: `test/repositories/link_thumbnail_fetcher_test.dart`

**Interfaces:**
- Produces:
  - `class LinkThumbnailException implements Exception { final String message; }`
  - `class LinkThumbnailFetcher { bool isSupportedUrl(String url); Future<String> fetchThumbnailUrl(String url); Future<void> downloadImage(String imageUrl, String outputPath); }`
- Scope trim: a single `og:image` scrape covers all three platforms (TikTok's video pages carry `og:image` cover thumbnails too), so this skips a separate TikTok-oEmbed code path — one mechanism, one thing to maintain.

- [ ] **Step 1: Write the failing tests (mocking `http.Client`)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sticker_creator/repositories/link_thumbnail_fetcher.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  late MockClient client;
  late LinkThumbnailFetcher fetcher;

  setUp(() {
    client = MockClient();
    fetcher = LinkThumbnailFetcher(client: client);
  });

  group('isSupportedUrl', () {
    test('accepts TikTok, Instagram, Pinterest hosts', () {
      expect(fetcher.isSupportedUrl('https://www.tiktok.com/@user/video/123'), isTrue);
      expect(fetcher.isSupportedUrl('https://instagram.com/p/abc'), isTrue);
      expect(fetcher.isSupportedUrl('https://pin.it/abc'), isTrue);
    });

    test('rejects other hosts', () {
      expect(fetcher.isSupportedUrl('https://example.com/foo'), isFalse);
      expect(fetcher.isSupportedUrl('not a url'), isFalse);
    });
  });

  group('fetchThumbnailUrl', () {
    test('extracts the og:image content from the fetched page', () async {
      when(() => client.get(any(), headers: any(named: 'headers'))).thenAnswer(
        (_) async => http.Response(
          '<html><head><meta property="og:image" content="https://example.com/thumb.jpg"></head></html>',
          200,
        ),
      );

      final thumbnail = await fetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc');

      expect(thumbnail, 'https://example.com/thumb.jpg');
    });

    test('throws when the page has no og:image tag', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('<html></html>', 200));

      expect(
        () => fetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc'),
        throwsA(isA<LinkThumbnailException>()),
      );
    });

    test('throws on a non-200 response', () async {
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('', 404));

      expect(
        () => fetcher.fetchThumbnailUrl('https://www.instagram.com/p/abc'),
        throwsA(isA<LinkThumbnailException>()),
      );
    });

    test('throws for an unsupported host without making a request', () async {
      expect(
        () => fetcher.fetchThumbnailUrl('https://example.com/foo'),
        throwsA(isA<LinkThumbnailException>()),
      );
      verifyNever(() => client.get(any(), headers: any(named: 'headers')));
    });
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/repositories/link_thumbnail_fetcher_test.dart`
Expected: FAIL (`link_thumbnail_fetcher.dart` doesn't exist yet)

- [ ] **Step 3: Write `lib/repositories/link_thumbnail_fetcher.dart`**

```dart
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class LinkThumbnailException implements Exception {
  LinkThumbnailException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LinkThumbnailFetcher {
  LinkThumbnailFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _supportedHosts = ['tiktok.com', 'instagram.com', 'pinterest.com', 'pin.it'];

  bool isSupportedUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final host = uri.host.toLowerCase();
    return _supportedHosts.any((h) => host == h || host.endsWith('.$h'));
  }

  /// Fetches the page at [url] and returns its og:image thumbnail URL.
  Future<String> fetchThumbnailUrl(String url) async {
    if (!isSupportedUrl(url)) {
      throw LinkThumbnailException(
        'Unsupported link: only TikTok, Instagram, and Pinterest links are supported',
      );
    }
    final response = await _client.get(
      Uri.parse(url),
      headers: {'User-Agent': 'Mozilla/5.0 (compatible; StickerCreator/1.0)'},
    );
    if (response.statusCode != 200) {
      throw LinkThumbnailException('Could not load link (HTTP ${response.statusCode})');
    }
    final document = html_parser.parse(response.body);
    final content = document.querySelector('meta[property="og:image"]')?.attributes['content'];
    if (content == null || content.isEmpty) {
      throw LinkThumbnailException('No preview image found for this link');
    }
    return content;
  }

  /// Downloads the image at [imageUrl] and writes it to [outputPath].
  Future<void> downloadImage(String imageUrl, String outputPath) async {
    final response = await _client.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      throw LinkThumbnailException('Could not download preview image');
    }
    await File(outputPath).writeAsBytes(response.bodyBytes);
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/repositories/link_thumbnail_fetcher_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/link_thumbnail_fetcher.dart test/repositories/link_thumbnail_fetcher_test.dart
git commit -m "Add LinkThumbnailFetcher (og:image scrape for TikTok/Instagram/Pinterest links)"
```

---

## Task 9: Share-sheet wiring

**Files:**
- Modify: `lib/repositories/import_repository.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: `test/repositories/import_repository_share_test.dart`

**Interfaces:**
- Produces: adds `Stream<String> getSharedUrlStream()` and `Future<String?> getInitialSharedUrl()` to `ImportRepository`, both filtering `receive_sharing_intent`'s `SharedMediaFile` list down to the first item whose `path` looks like a supported link.

- [ ] **Step 1: Add Android intent-filters for receiving shared text**

In `android/app/src/main/AndroidManifest.xml`, inside the `<activity>` block for `.MainActivity` (alongside the existing `MAIN`/`LAUNCHER` intent-filter), add:

```xml
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="text/*" />
</intent-filter>
```

Also change that activity's `android:launchMode` from `singleTop` to `singleTask` (required by `receive_sharing_intent` so re-shares while the app is open don't spawn a duplicate instance).

- [ ] **Step 2: Write the failing test (pure filtering logic, no platform channel)**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sticker_creator/repositories/import_repository.dart';

void main() {
  test('firstSupportedUrl returns the first text share that is a URL', () {
    final shares = [
      SharedMediaFile(path: 'just some text', type: SharedMediaType.text),
      SharedMediaFile(path: 'https://www.tiktok.com/@user/video/123', type: SharedMediaType.text),
    ];

    expect(firstSupportedUrl(shares), 'https://www.tiktok.com/@user/video/123');
  });

  test('firstSupportedUrl returns null when nothing looks like a URL', () {
    final shares = [SharedMediaFile(path: 'no links here', type: SharedMediaType.text)];

    expect(firstSupportedUrl(shares), isNull);
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/repositories/import_repository_share_test.dart`
Expected: FAIL (`firstSupportedUrl` doesn't exist yet)

- [ ] **Step 4: Add the share-sheet methods to `lib/repositories/import_repository.dart`**

```dart
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
```
(add to the existing import block)

```dart
/// Returns the first shared item whose text looks like an http(s) URL, or
/// null if none does. Pulled out as a top-level function so it's testable
/// without touching the `receive_sharing_intent` platform channel.
String? firstSupportedUrl(List<SharedMediaFile> shares) {
  for (final share in shares) {
    final uri = Uri.tryParse(share.path);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return share.path;
    }
  }
  return null;
}
```

Add these two methods to the `ImportRepository` class body:

```dart
  Stream<String> getSharedUrlStream() {
    return ReceiveSharingIntent.instance.getMediaStream().map(firstSupportedUrl).where((url) => url != null).cast<String>();
  }

  Future<String?> getInitialSharedUrl() async {
    final shares = await ReceiveSharingIntent.instance.getInitialMedia();
    final url = firstSupportedUrl(shares);
    await ReceiveSharingIntent.instance.reset();
    return url;
  }
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/repositories/import_repository_share_test.dart`
Expected: PASS. If `receive_sharing_intent`'s installed version has renamed `getMediaStream`/`getInitialMedia`/`SharedMediaFile.path`, adjust the call sites to match — the intent (stream of incoming shares + one-shot initial share, filtered to URLs) is what to preserve.

- [ ] **Step 6: Commit**

```bash
git add lib/repositories/import_repository.dart android/app/src/main/AndroidManifest.xml test/repositories/import_repository_share_test.dart
git commit -m "Wire OS share-sheet intake for TikTok/Instagram/Pinterest links (Android)"
```

**Note — iOS share extension:** `receive_sharing_intent`'s iOS side needs a Share Extension Xcode target (App Groups capability, `ShareViewController` subclassing `RSIShareViewController`) that can't be scripted via text edits alone. Do this step manually in Xcode following the package's README before iOS share-sheet testing; it doesn't block Android or the paste-URL flow (Task 15), which work without it.

---

## Task 10: ImportBloc

**Files:**
- Create: `lib/blocs/import/import_event.dart`
- Create: `lib/blocs/import/import_state.dart`
- Create: `lib/blocs/import/import_bloc.dart`
- Test: `test/blocs/import_bloc_test.dart`

**Interfaces:**
- Consumes: `ImportRepository` (Tasks 7–9), `StickerProcessor` (Tasks 4–6), `LinkThumbnailFetcher` (Task 8).
- Produces:
  - Events: `PickStaticImagesRequested`, `PickGifRequested`, `LinkUrlSubmitted(String url)`, `LinkThumbnailConfirmed`
  - States: `ImportInitial`, `ImportProcessing`, `ImportThumbnailPreview(String localPreviewPath)`, `ImportReady(List<String> processedFilePaths)`, `ImportFailure(String message)`
  - `class ImportBloc extends Bloc<ImportEvent, ImportState>`

- [ ] **Step 1: Write `lib/blocs/import/import_event.dart`**

```dart
import 'package:equatable/equatable.dart';

sealed class ImportEvent extends Equatable {
  const ImportEvent();

  @override
  List<Object?> get props => [];
}

class PickStaticImagesRequested extends ImportEvent {
  const PickStaticImagesRequested();
}

class PickGifRequested extends ImportEvent {
  const PickGifRequested();
}

class LinkUrlSubmitted extends ImportEvent {
  const LinkUrlSubmitted(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

class LinkThumbnailConfirmed extends ImportEvent {
  const LinkThumbnailConfirmed();
}
```

- [ ] **Step 2: Write `lib/blocs/import/import_state.dart`**

```dart
import 'package:equatable/equatable.dart';

sealed class ImportState extends Equatable {
  const ImportState();

  @override
  List<Object?> get props => [];
}

class ImportInitial extends ImportState {
  const ImportInitial();
}

class ImportProcessing extends ImportState {
  const ImportProcessing();
}

class ImportThumbnailPreview extends ImportState {
  const ImportThumbnailPreview(this.localPreviewPath);

  final String localPreviewPath;

  @override
  List<Object?> get props => [localPreviewPath];
}

class ImportReady extends ImportState {
  const ImportReady(this.processedFilePaths);

  final List<String> processedFilePaths;

  @override
  List<Object?> get props => [processedFilePaths];
}

class ImportFailure extends ImportState {
  const ImportFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
```

- [ ] **Step 3: Write the failing test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sticker_creator/blocs/import/import_bloc.dart';
import 'package:sticker_creator/blocs/import/import_event.dart';
import 'package:sticker_creator/blocs/import/import_state.dart';
import 'package:sticker_creator/repositories/import_repository.dart';
import 'package:sticker_creator/repositories/link_thumbnail_fetcher.dart';
import 'package:sticker_creator/repositories/sticker_processor.dart';

class MockImportRepository extends Mock implements ImportRepository {}
class MockStickerProcessor extends Mock implements StickerProcessor {}
class MockLinkThumbnailFetcher extends Mock implements LinkThumbnailFetcher {}

void main() {
  late MockImportRepository importRepository;
  late MockStickerProcessor stickerProcessor;
  late MockLinkThumbnailFetcher thumbnailFetcher;

  setUp(() {
    importRepository = MockImportRepository();
    stickerProcessor = MockStickerProcessor();
    thumbnailFetcher = MockLinkThumbnailFetcher();
  });

  ImportBloc buildBloc() => ImportBloc(
        importRepository: importRepository,
        stickerProcessor: stickerProcessor,
        thumbnailFetcher: thumbnailFetcher,
      );

  blocTest<ImportBloc, ImportState>(
    'PickStaticImagesRequested processes each picked image and emits ImportReady',
    setUp: () {
      when(() => importRepository.pickStaticImages())
          .thenAnswer((_) async => ['/tmp/a.jpg']);
      when(() => stickerProcessor.encodeStatic(any(), any()))
          .thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const PickStaticImagesRequested()),
    expect: () => [
      const ImportProcessing(),
      isA<ImportReady>(),
    ],
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted fetches and previews a thumbnail',
    setUp: () {
      when(() => thumbnailFetcher.fetchThumbnailUrl(any()))
          .thenAnswer((_) async => 'https://example.com/thumb.jpg');
      when(() => thumbnailFetcher.downloadImage(any(), any()))
          .thenAnswer((_) async {});
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    expect: () => [
      const ImportProcessing(),
      isA<ImportThumbnailPreview>(),
    ],
  );

  blocTest<ImportBloc, ImportState>(
    'LinkUrlSubmitted emits ImportFailure when the fetcher throws',
    setUp: () {
      when(() => thumbnailFetcher.fetchThumbnailUrl(any()))
          .thenThrow(LinkThumbnailException('No preview image found for this link'));
    },
    build: buildBloc,
    act: (bloc) => bloc.add(const LinkUrlSubmitted('https://www.instagram.com/p/abc')),
    expect: () => [
      const ImportProcessing(),
      const ImportFailure('No preview image found for this link'),
    ],
  );
}
```

- [ ] **Step 4: Run to verify failure**

Run: `flutter test test/blocs/import_bloc_test.dart`
Expected: FAIL (`import_bloc.dart` doesn't exist yet)

- [ ] **Step 5: Write `lib/blocs/import/import_bloc.dart`**

```dart
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../repositories/import_repository.dart';
import '../../repositories/link_thumbnail_fetcher.dart';
import '../../repositories/sticker_processor.dart';
import 'import_event.dart';
import 'import_state.dart';

class ImportBloc extends Bloc<ImportEvent, ImportState> {
  ImportBloc({
    required this.importRepository,
    required this.stickerProcessor,
    required this.thumbnailFetcher,
  }) : super(const ImportInitial()) {
    on<PickStaticImagesRequested>(_onPickStaticImages);
    on<PickGifRequested>(_onPickGif);
    on<LinkUrlSubmitted>(_onLinkUrlSubmitted);
    on<LinkThumbnailConfirmed>(_onLinkThumbnailConfirmed);
  }

  final ImportRepository importRepository;
  final StickerProcessor stickerProcessor;
  final LinkThumbnailFetcher thumbnailFetcher;

  String? _pendingThumbnailPath;

  Future<String> _newOutputPath(String extension) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    return p.join(dir.path, 'stickers', '$id.$extension');
  }

  Future<void> _onPickStaticImages(
    PickStaticImagesRequested event,
    Emitter<ImportState> emit,
  ) async {
    emit(const ImportProcessing());
    try {
      final picked = await importRepository.pickStaticImages();
      final outputs = <String>[];
      for (final inputPath in picked) {
        final outputPath = await _newOutputPath('webp');
        await Directory(p.dirname(outputPath)).create(recursive: true);
        await stickerProcessor.encodeStatic(inputPath, outputPath);
        outputs.add(outputPath);
      }
      emit(ImportReady(outputs));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }

  Future<void> _onPickGif(
    PickGifRequested event,
    Emitter<ImportState> emit,
  ) async {
    emit(const ImportProcessing());
    try {
      final inputPath = await importRepository.pickGifFile();
      if (inputPath == null) {
        emit(const ImportInitial());
        return;
      }
      final outputPath = await _newOutputPath('webp');
      await Directory(p.dirname(outputPath)).create(recursive: true);
      await stickerProcessor.encodeAnimatedGif(inputPath, outputPath);
      emit(ImportReady([outputPath]));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }

  Future<void> _onLinkUrlSubmitted(
    LinkUrlSubmitted event,
    Emitter<ImportState> emit,
  ) async {
    emit(const ImportProcessing());
    try {
      final thumbnailUrl = await thumbnailFetcher.fetchThumbnailUrl(event.url);
      final localPath = await _newOutputPath('jpg');
      await Directory(p.dirname(localPath)).create(recursive: true);
      await thumbnailFetcher.downloadImage(thumbnailUrl, localPath);
      _pendingThumbnailPath = localPath;
      emit(ImportThumbnailPreview(localPath));
    } on LinkThumbnailException catch (e) {
      emit(ImportFailure(e.message));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }

  Future<void> _onLinkThumbnailConfirmed(
    LinkThumbnailConfirmed event,
    Emitter<ImportState> emit,
  ) async {
    final pending = _pendingThumbnailPath;
    if (pending == null) return;
    emit(const ImportProcessing());
    try {
      final outputPath = await _newOutputPath('webp');
      await stickerProcessor.encodeStatic(pending, outputPath);
      emit(ImportReady([outputPath]));
    } catch (e) {
      emit(ImportFailure(e.toString()));
    }
  }
}
```

- [ ] **Step 6: Run to verify pass**

Run: `flutter test test/blocs/import_bloc_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/blocs/import test/blocs/import_bloc_test.dart
git commit -m "Add ImportBloc tying direct/link import to the processing pipeline"
```

---

## Task 11: PackListBloc

**Files:**
- Create: `lib/blocs/pack_list/pack_list_event.dart`
- Create: `lib/blocs/pack_list/pack_list_state.dart`
- Create: `lib/blocs/pack_list/pack_list_bloc.dart`
- Test: `test/blocs/pack_list_bloc_test.dart`

**Interfaces:**
- Consumes: `PackRepository` (Task 2).
- Produces:
  - Events: `PackListLoadRequested`, `PackCreated(String name, String publisherName)`, `PackRenamed(String id, String newName)`, `PackDeleted(String id)`
  - States: `PackListLoading`, `PackListLoaded(List<StickerPack> packs)`
  - `class PackListBloc extends Bloc<PackListEvent, PackListState>`

- [ ] **Step 1: Write `lib/blocs/pack_list/pack_list_event.dart`**

```dart
import 'package:equatable/equatable.dart';

sealed class PackListEvent extends Equatable {
  const PackListEvent();

  @override
  List<Object?> get props => [];
}

class PackListLoadRequested extends PackListEvent {
  const PackListLoadRequested();
}

class PackCreated extends PackListEvent {
  const PackCreated(this.name, this.publisherName);

  final String name;
  final String publisherName;

  @override
  List<Object?> get props => [name, publisherName];
}

class PackRenamed extends PackListEvent {
  const PackRenamed(this.id, this.newName);

  final String id;
  final String newName;

  @override
  List<Object?> get props => [id, newName];
}

class PackDeleted extends PackListEvent {
  const PackDeleted(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}
```

- [ ] **Step 2: Write `lib/blocs/pack_list/pack_list_state.dart`**

```dart
import 'package:equatable/equatable.dart';

import '../../models/sticker_pack.dart';

sealed class PackListState extends Equatable {
  const PackListState();

  @override
  List<Object?> get props => [];
}

class PackListLoading extends PackListState {
  const PackListLoading();
}

class PackListLoaded extends PackListState {
  const PackListLoaded(this.packs);

  final List<StickerPack> packs;

  @override
  List<Object?> get props => [packs];
}
```

- [ ] **Step 3: Write the failing test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sticker_creator/blocs/pack_list/pack_list_bloc.dart';
import 'package:sticker_creator/blocs/pack_list/pack_list_event.dart';
import 'package:sticker_creator/blocs/pack_list/pack_list_state.dart';
import 'package:sticker_creator/models/sticker_pack.dart';
import 'package:sticker_creator/repositories/pack_repository.dart';

class MockPackRepository extends Mock implements PackRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(StickerPack(id: 'x', name: 'x', publisherName: 'x'));
  });

  late MockPackRepository repository;

  setUp(() => repository = MockPackRepository());

  blocTest<PackListBloc, PackListState>(
    'PackListLoadRequested loads packs from the repository',
    setUp: () => when(() => repository.getAllPacks()).thenReturn(
      [StickerPack(id: '1', name: 'A', publisherName: 'Me')],
    ),
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackListLoadRequested()),
    expect: () => [isA<PackListLoaded>()],
  );

  blocTest<PackListBloc, PackListState>(
    'PackCreated saves a new pack then reloads',
    setUp: () {
      when(() => repository.savePack(any())).thenAnswer((_) async {});
      when(() => repository.getAllPacks()).thenReturn(
        [StickerPack(id: 'new', name: 'New Pack', publisherName: 'Me')],
      );
    },
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackCreated('New Pack', 'Me')),
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      final saved = captured.single as StickerPack;
      expect(saved.name, 'New Pack');
      expect(saved.publisherName, 'Me');
    },
  );

  blocTest<PackListBloc, PackListState>(
    'PackDeleted removes a pack then reloads',
    setUp: () {
      when(() => repository.deletePack('1')).thenAnswer((_) async {});
      when(() => repository.getAllPacks()).thenReturn([]);
    },
    build: () => PackListBloc(repository),
    act: (bloc) => bloc.add(const PackDeleted('1')),
    expect: () => [const PackListLoaded([])],
  );
}
```

- [ ] **Step 4: Run to verify failure**

Run: `flutter test test/blocs/pack_list_bloc_test.dart`
Expected: FAIL (`pack_list_bloc.dart` doesn't exist yet)

- [ ] **Step 5: Write `lib/blocs/pack_list/pack_list_bloc.dart`**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/sticker_pack.dart';
import '../../repositories/pack_repository.dart';
import 'pack_list_event.dart';
import 'pack_list_state.dart';

class PackListBloc extends Bloc<PackListEvent, PackListState> {
  PackListBloc(this._repository) : super(const PackListLoading()) {
    on<PackListLoadRequested>(_onLoad);
    on<PackCreated>(_onCreated);
    on<PackRenamed>(_onRenamed);
    on<PackDeleted>(_onDeleted);
  }

  final PackRepository _repository;

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

  void _emitLoaded(Emitter<PackListState> emit) {
    emit(PackListLoaded(_repository.getAllPacks()));
  }

  Future<void> _onLoad(PackListLoadRequested event, Emitter<PackListState> emit) async {
    _emitLoaded(emit);
  }

  Future<void> _onCreated(PackCreated event, Emitter<PackListState> emit) async {
    await _repository.savePack(
      StickerPack(id: _newId(), name: event.name, publisherName: event.publisherName),
    );
    _emitLoaded(emit);
  }

  Future<void> _onRenamed(PackRenamed event, Emitter<PackListState> emit) async {
    final pack = _repository.getPack(event.id);
    if (pack == null) return;
    pack.name = event.newName;
    await _repository.savePack(pack);
    _emitLoaded(emit);
  }

  Future<void> _onDeleted(PackDeleted event, Emitter<PackListState> emit) async {
    await _repository.deletePack(event.id);
    _emitLoaded(emit);
  }
}
```

- [ ] **Step 6: Run to verify pass**

Run: `flutter test test/blocs/pack_list_bloc_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/blocs/pack_list test/blocs/pack_list_bloc_test.dart
git commit -m "Add PackListBloc"
```

---

## Task 12: PackDetailBloc

**Files:**
- Create: `lib/blocs/pack_detail/pack_detail_event.dart`
- Create: `lib/blocs/pack_detail/pack_detail_state.dart`
- Create: `lib/blocs/pack_detail/pack_detail_bloc.dart`
- Test: `test/blocs/pack_detail_bloc_test.dart`

**Interfaces:**
- Consumes: `PackRepository` (Task 2), `StickerProcessor.encodeTrayIcon` (Task 6).
- Produces:
  - Events: `PackDetailLoadRequested(String packId)`, `StickersAdded(List<String> processedFilePaths, StickerType type)`, `StickerRemoved(String stickerId)`, `TrayIconSet(String croppedImagePath)`
  - States: `PackDetailLoading`, `PackDetailLoaded(StickerPack pack, bool canAddToWhatsApp)`, `PackDetailNotFound`
  - `class PackDetailBloc extends Bloc<PackDetailEvent, PackDetailState>`
  - `canAddToWhatsApp` is `pack.stickers.length >= 3 && pack.stickers.length <= 30 && pack.trayIconPath != null` — this is the gate the spec requires before "Add to WhatsApp" is enabled.

- [ ] **Step 1: Write `lib/blocs/pack_detail/pack_detail_event.dart`**

```dart
import 'package:equatable/equatable.dart';

import '../../models/sticker.dart';

sealed class PackDetailEvent extends Equatable {
  const PackDetailEvent();

  @override
  List<Object?> get props => [];
}

class PackDetailLoadRequested extends PackDetailEvent {
  const PackDetailLoadRequested(this.packId);

  final String packId;

  @override
  List<Object?> get props => [packId];
}

class StickersAdded extends PackDetailEvent {
  const StickersAdded(this.processedFilePaths, this.type);

  final List<String> processedFilePaths;
  final StickerType type;

  @override
  List<Object?> get props => [processedFilePaths, type];
}

class StickerRemoved extends PackDetailEvent {
  const StickerRemoved(this.stickerId);

  final String stickerId;

  @override
  List<Object?> get props => [stickerId];
}

class TrayIconSet extends PackDetailEvent {
  const TrayIconSet(this.croppedImagePath);

  final String croppedImagePath;

  @override
  List<Object?> get props => [croppedImagePath];
}
```

- [ ] **Step 2: Write `lib/blocs/pack_detail/pack_detail_state.dart`**

```dart
import 'package:equatable/equatable.dart';

import '../../models/sticker_pack.dart';

sealed class PackDetailState extends Equatable {
  const PackDetailState();

  @override
  List<Object?> get props => [];
}

class PackDetailLoading extends PackDetailState {
  const PackDetailLoading();
}

class PackDetailNotFound extends PackDetailState {
  const PackDetailNotFound();
}

class PackDetailLoaded extends PackDetailState {
  const PackDetailLoaded(this.pack, this.canAddToWhatsApp);

  final StickerPack pack;
  final bool canAddToWhatsApp;

  @override
  List<Object?> get props => [pack, canAddToWhatsApp];
}
```

- [ ] **Step 3: Write the failing test**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sticker_creator/blocs/pack_detail/pack_detail_bloc.dart';
import 'package:sticker_creator/blocs/pack_detail/pack_detail_event.dart';
import 'package:sticker_creator/blocs/pack_detail/pack_detail_state.dart';
import 'package:sticker_creator/models/sticker.dart';
import 'package:sticker_creator/models/sticker_pack.dart';
import 'package:sticker_creator/repositories/pack_repository.dart';
import 'package:sticker_creator/repositories/sticker_processor.dart';

class MockPackRepository extends Mock implements PackRepository {}
class MockStickerProcessor extends Mock implements StickerProcessor {}

StickerPack _packWith(int stickerCount, {String? trayIconPath}) => StickerPack(
      id: 'p1',
      name: 'Pack',
      publisherName: 'Me',
      trayIconPath: trayIconPath,
      stickers: [
        for (var i = 0; i < stickerCount; i++)
          Sticker(id: 's$i', filePath: '/tmp/s$i.webp', type: StickerType.static_),
      ],
    );

void main() {
  late MockPackRepository repository;
  late MockStickerProcessor processor;

  setUp(() {
    repository = MockPackRepository();
    processor = MockStickerProcessor();
  });

  PackDetailBloc buildBloc() => PackDetailBloc(repository: repository, stickerProcessor: processor);

  blocTest<PackDetailBloc, PackDetailState>(
    'canAddToWhatsApp is false with fewer than 3 stickers',
    setUp: () => when(() => repository.getPack('p1')).thenReturn(_packWith(2, trayIconPath: '/tmp/tray.png')),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('p1')),
    expect: () => [
      isA<PackDetailLoaded>().having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isFalse),
    ],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'canAddToWhatsApp is true with 3-30 stickers and a tray icon',
    setUp: () => when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png')),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('p1')),
    expect: () => [
      isA<PackDetailLoaded>().having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isTrue),
    ],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'canAddToWhatsApp is false without a tray icon even at 3 stickers',
    setUp: () => when(() => repository.getPack('p1')).thenReturn(_packWith(3)),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('p1')),
    expect: () => [
      isA<PackDetailLoaded>().having((s) => s.canAddToWhatsApp, 'canAddToWhatsApp', isFalse),
    ],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'PackDetailLoadRequested emits PackDetailNotFound for a missing pack',
    setUp: () => when(() => repository.getPack('missing')).thenReturn(null),
    build: buildBloc,
    act: (bloc) => bloc.add(const PackDetailLoadRequested('missing')),
    expect: () => [const PackDetailNotFound()],
  );

  blocTest<PackDetailBloc, PackDetailState>(
    'StickerRemoved removes the sticker and re-saves the pack',
    setUp: () {
      when(() => repository.getPack('p1')).thenReturn(_packWith(3, trayIconPath: '/tmp/tray.png'));
      when(() => repository.savePack(any())).thenAnswer((_) async {});
    },
    build: buildBloc,
    seed: () => PackDetailLoaded(_packWith(3, trayIconPath: '/tmp/tray.png'), true),
    act: (bloc) => bloc.add(const StickerRemoved('s0')),
    verify: (_) {
      final captured = verify(() => repository.savePack(captureAny())).captured;
      final saved = captured.single as StickerPack;
      expect(saved.stickers.any((s) => s.id == 's0'), isFalse);
    },
  );
}
```

- [ ] **Step 4: Run to verify failure**

Run: `flutter test test/blocs/pack_detail_bloc_test.dart`
Expected: FAIL (`pack_detail_bloc.dart` doesn't exist yet)

- [ ] **Step 5: Write `lib/blocs/pack_detail/pack_detail_bloc.dart`**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../models/sticker.dart';
import '../../models/sticker_pack.dart';
import '../../repositories/pack_repository.dart';
import '../../repositories/sticker_processor.dart';
import 'pack_detail_event.dart';
import 'pack_detail_state.dart';

class PackDetailBloc extends Bloc<PackDetailEvent, PackDetailState> {
  PackDetailBloc({required this.repository, required this.stickerProcessor})
      : super(const PackDetailLoading()) {
    on<PackDetailLoadRequested>(_onLoad);
    on<StickersAdded>(_onStickersAdded);
    on<StickerRemoved>(_onStickerRemoved);
    on<TrayIconSet>(_onTrayIconSet);
  }

  final PackRepository repository;
  final StickerProcessor stickerProcessor;

  String? _currentPackId;

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}';

  bool _canAdd(StickerPack pack) =>
      pack.stickers.length >= 3 && pack.stickers.length <= 30 && pack.trayIconPath != null;

  Future<void> _onLoad(PackDetailLoadRequested event, Emitter<PackDetailState> emit) async {
    _currentPackId = event.packId;
    final pack = repository.getPack(event.packId);
    if (pack == null) {
      emit(const PackDetailNotFound());
      return;
    }
    emit(PackDetailLoaded(pack, _canAdd(pack)));
  }

  Future<void> _onStickersAdded(StickersAdded event, Emitter<PackDetailState> emit) async {
    final pack = repository.getPack(_currentPackId!);
    if (pack == null) return;
    for (final path in event.processedFilePaths) {
      pack.stickers.add(Sticker(id: _newId(), filePath: path, type: event.type));
    }
    await repository.savePack(pack);
    emit(PackDetailLoaded(pack, _canAdd(pack)));
  }

  Future<void> _onStickerRemoved(StickerRemoved event, Emitter<PackDetailState> emit) async {
    final pack = repository.getPack(_currentPackId!);
    if (pack == null) return;
    pack.stickers.removeWhere((s) => s.id == event.stickerId);
    await repository.savePack(pack);
    emit(PackDetailLoaded(pack, _canAdd(pack)));
  }

  Future<void> _onTrayIconSet(TrayIconSet event, Emitter<PackDetailState> emit) async {
    final pack = repository.getPack(_currentPackId!);
    if (pack == null) return;
    pack.trayIconPath = event.croppedImagePath;
    await repository.savePack(pack);
    emit(PackDetailLoaded(pack, _canAdd(pack)));
  }
}
```

- [ ] **Step 6: Run to verify pass**

Run: `flutter test test/blocs/pack_detail_bloc_test.dart`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/blocs/pack_detail test/blocs/pack_detail_bloc_test.dart
git commit -m "Add PackDetailBloc with 3-30 sticker + tray icon validation gate"
```

---

## Task 13: WhatsAppHandoff — Dart platform channel wrapper

**Files:**
- Create: `lib/repositories/whatsapp_handoff.dart`
- Test: `test/repositories/whatsapp_handoff_test.dart`

**Interfaces:**
- Produces: `class WhatsAppHandoff { Future<bool> isWhatsAppInstalled(); Future<void> addPack(StickerPack pack); }` (constructor takes an optional `MethodChannel` for test injection).
- Consumes: `StickerPack` (Task 2). Native sides implemented in Tasks 14–15.

- [ ] **Step 1: Write the failing test (mocking the MethodChannel via `TestDefaultBinaryMessenger`)**

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_creator/models/sticker_pack.dart';
import 'package:sticker_creator/repositories/whatsapp_handoff.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('sticker_creator/whatsapp');
  final log = <MethodCall>[];
  late WhatsAppHandoff handoff;

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      switch (call.method) {
        case 'isWhatsAppInstalled':
          return true;
        case 'addPack':
          return null;
      }
      return null;
    });
    handoff = WhatsAppHandoff(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isWhatsAppInstalled forwards to the platform channel', () async {
    final result = await handoff.isWhatsAppInstalled();
    expect(result, isTrue);
    expect(log.single.method, 'isWhatsAppInstalled');
  });

  test('addPack sends pack id, name, publisher, and sticker file paths', () async {
    final pack = StickerPack(id: 'p1', name: 'My Pack', publisherName: 'Me', trayIconPath: '/tmp/tray.png');

    await handoff.addPack(pack);

    expect(log.single.method, 'addPack');
    final args = log.single.arguments as Map;
    expect(args['id'], 'p1');
    expect(args['name'], 'My Pack');
    expect(args['publisher'], 'Me');
    expect(args['trayIconPath'], '/tmp/tray.png');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/repositories/whatsapp_handoff_test.dart`
Expected: FAIL (`whatsapp_handoff.dart` doesn't exist yet)

- [ ] **Step 3: Write `lib/repositories/whatsapp_handoff.dart`**

```dart
import 'package:flutter/services.dart';

import '../models/sticker_pack.dart';

class WhatsAppHandoff {
  WhatsAppHandoff({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('sticker_creator/whatsapp');

  final MethodChannel _channel;

  Future<bool> isWhatsAppInstalled() async {
    final result = await _channel.invokeMethod<bool>('isWhatsAppInstalled');
    return result ?? false;
  }

  /// Sends [pack] to the native side, which serves it to WhatsApp (Android
  /// ContentProvider + intent, iOS pasteboard + URL scheme) and triggers the
  /// "Add to WhatsApp" UI.
  Future<void> addPack(StickerPack pack) async {
    await _channel.invokeMethod<void>('addPack', {
      'id': pack.id,
      'name': pack.name,
      'publisher': pack.publisherName,
      'trayIconPath': pack.trayIconPath,
      'stickers': [
        for (final sticker in pack.stickers)
          {'id': sticker.id, 'filePath': sticker.filePath, 'type': sticker.type.name},
      ],
    });
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/repositories/whatsapp_handoff_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/repositories/whatsapp_handoff.dart test/repositories/whatsapp_handoff_test.dart
git commit -m "Add WhatsAppHandoff Dart platform channel wrapper"
```

---

## Task 14: WhatsAppHandoff — Android native

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/sticker_creator/MainActivity.kt`
- Create: `android/app/src/main/kotlin/com/example/sticker_creator/StickerContentProvider.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Consumes: the `sticker_creator/whatsapp` MethodChannel calls `isWhatsAppInstalled` / `addPack` defined in Task 13.
- Produces: a working Android "Add to WhatsApp" handoff, verified manually on a device with WhatsApp installed (native platform code isn't unit-testable from Dart).

Per the spec: check pub.dev first for a current, maintained plugin bundling this contract (e.g. `whatsapp_stickers_handler`) — if one fits, wire it behind the same `sticker_creator/whatsapp` MethodChannel names instead of hand-writing the `ContentProvider` below. The steps below are the concrete fallback, written directly against WhatsApp's published contract (github.com/WhatsApp/stickers).

- [ ] **Step 1: Declare the ContentProvider in the manifest**

In `android/app/src/main/AndroidManifest.xml`, inside `<application>`, add (as a sibling of the existing `<activity>`):

```xml
<provider
    android:name=".StickerContentProvider"
    android:authorities="${applicationId}.stickercontentprovider"
    android:enabled="true"
    android:exported="true"
    android:readPermission="com.whatsapp.sticker.READ" />
```

- [ ] **Step 2: Write `StickerContentProvider.kt`**

This provider reads pack data from a JSON file the Dart side writes before calling `addPack` (simplest way to hand data from Dart to a `ContentProvider`, which Flutter's MethodChannel can't populate directly — the provider is queried by WhatsApp, not invoked by our own app).

```kotlin
package com.example.sticker_creator

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File

class StickerContentProvider : ContentProvider() {
    private val authority get() = "${context!!.packageName}.stickercontentprovider"

    private fun packsFile() = File(context!!.filesDir, "whatsapp_export/packs.json")

    private fun readPacks(): JSONObject =
        JSONObject(packsFile().readText())

    override fun onCreate(): Boolean = true

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                        selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val segments = uri.pathSegments
        return when (segments.getOrNull(0)) {
            "metadata" -> queryMetadata()
            "stickers" -> queryStickers(segments.getOrNull(1))
            else -> null
        }
    }

    private fun queryMetadata(): Cursor {
        val cursor = MatrixCursor(arrayOf(
            "sticker_pack_identifier", "sticker_pack_name", "sticker_pack_publisher",
            "sticker_pack_icon", "android_play_store_link", "ios_app_download_link",
            "publisher_email", "publisher_website", "privacy_policy_website",
            "license_agreement_website", "image_data_version", "avoid_cache",
            "animated_sticker_pack",
        ))
        val packs = readPacks()
        for (id in packs.keys()) {
            val pack = packs.getJSONObject(id)
            cursor.addRow(arrayOf(
                id, pack.getString("name"), pack.getString("publisher"),
                pack.getString("trayIconFileName"), "", "", "", "", "", "",
                "1", 0, if (pack.getBoolean("isAnimated")) 1 else 0,
            ))
        }
        return cursor
    }

    private fun queryStickers(packId: String?): Cursor {
        val cursor = MatrixCursor(arrayOf("sticker_file_name", "sticker_emoji"))
        if (packId == null) return cursor
        val pack = readPacks().getJSONObject(packId)
        val stickers = pack.getJSONArray("stickers")
        for (i in 0 until stickers.length()) {
            cursor.addRow(arrayOf(stickers.getJSONObject(i).getString("fileName"), ""))
        }
        return cursor
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        val segments = uri.pathSegments
        if (segments.getOrNull(0) != "stickers_asset") return null
        val packId = segments.getOrNull(1) ?: return null
        val fileName = segments.getOrNull(2) ?: return null
        val pack = readPacks().getJSONObject(packId)
        val filePath = if (fileName == pack.getString("trayIconFileName")) {
            pack.getString("trayIconPath")
        } else {
            val stickers = pack.getJSONArray("stickers")
            (0 until stickers.length())
                .map { stickers.getJSONObject(it) }
                .first { it.getString("fileName") == fileName }
                .getString("filePath")
        }
        val pfd = ParcelFileDescriptor.open(File(filePath), ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
```

- [ ] **Step 3: Wire the MethodChannel in `MainActivity.kt`**

Replace the file's contents with:

```kotlin
package com.example.sticker_creator

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "sticker_creator/whatsapp"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWhatsAppInstalled" -> result.success(isWhatsAppInstalled())
                "addPack" -> {
                    addPack(call.arguments as Map<*, *>)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isWhatsAppInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo("com.whatsapp", PackageManager.GET_ACTIVITIES)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun addPack(args: Map<*, *>) {
        val packId = args["id"] as String
        val stickers = args["stickers"] as List<*>

        val packsFile = File(filesDir, "whatsapp_export/packs.json")
        packsFile.parentFile?.mkdirs()
        val allPacks = if (packsFile.exists()) JSONObject(packsFile.readText()) else JSONObject()

        val packJson = JSONObject().apply {
            put("name", args["name"])
            put("publisher", args["publisher"])
            put("trayIconPath", args["trayIconPath"])
            put("trayIconFileName", "tray_$packId.png")
            put("isAnimated", stickers.any { (it as Map<*, *>)["type"] == "animated" })
            put("stickers", JSONArray(stickers.mapIndexed { i, s ->
                val sticker = s as Map<*, *>
                JSONObject().apply {
                    put("fileName", "sticker_${packId}_$i.webp")
                    put("filePath", sticker["filePath"])
                }
            }))
        }
        allPacks.put(packId, packJson)
        packsFile.writeText(allPacks.toString())

        val intent = Intent().apply {
            action = "com.whatsapp.intent.action.ENQUEUE_STICKER_PACK"
            putExtra("sticker_pack_id", packId)
            putExtra("sticker_pack_authority", "$packageName.stickercontentprovider")
            putExtra("sticker_pack_name", args["name"] as String)
        }
        try {
            startActivityForResult(intent, 200)
        } catch (e: ActivityNotFoundException) {
            // Dart side already checks isWhatsAppInstalled() before calling addPack,
            // but handle the race (WhatsApp uninstalled mid-flow) without crashing.
        }
    }
}
```

Note: `sticker_file_name`/`fileName` values here are synthetic (`sticker_<packId>_<i>.webp`), not the real basenames of files under our own storage — `openAssetFile` maps them back to real paths by matching `filePath`, not by filename, so this is consistent. Verify column/URI names in Step 2 and this step against the current github.com/WhatsApp/stickers sample during implementation, since WhatsApp can revise the exact contract.

- [ ] **Step 4: Manual verification (cannot be automated)**

On a physical Android device or emulator with WhatsApp installed:
1. `flutter run` in release mode (`flutter run --release`) since some WhatsApp versions reject debug-signed callers for the sticker intent.
2. Create a pack with ≥3 stickers and a tray icon, tap "Add to WhatsApp" (added to the UI in Task 17).
3. Confirm WhatsApp opens its sticker-pack-add screen showing the correct name, tray icon, and all stickers.
4. Confirm tapping "Add" in WhatsApp succeeds and the pack appears in WhatsApp's sticker tray.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/example/sticker_creator android/app/src/main/AndroidManifest.xml
git commit -m "Add Android WhatsApp handoff (ContentProvider + ENQUEUE_STICKER_PACK intent)"
```

---

## Task 15: WhatsAppHandoff — iOS native

**Files:**
- Modify: `ios/Runner/AppDelegate.swift`

**Interfaces:**
- Consumes: the `sticker_creator/whatsapp` MethodChannel calls `isWhatsAppInstalled` / `addPack` defined in Task 13.
- Produces: a working iOS "Add to WhatsApp" handoff via `UIPasteboard` + `whatsapp://stickerPack`, verified manually on a device with WhatsApp installed.

The general iOS protocol (write pack+sticker JSON and binary data to the general pasteboard with a short expiration, then open `whatsapp://stickerPack`) is well-established, but WhatsApp's exact pasteboard dictionary key names are documented on WhatsApp's own iOS third-party-sticker integration guide and can be revised by WhatsApp independently of this plan — **before writing code, look up the current guide and confirm the key names below still match**; adjust the dictionary keys in Step 1 to whatever the current guide specifies if they've changed.

- [ ] **Step 1: Confirm current pasteboard contract, then write the handoff in `AppDelegate.swift`**

Add this above `AppDelegate`:

```swift
import UIKit

struct WhatsAppStickerExporter {
    static func isInstalled() -> Bool {
        guard let url = URL(string: "whatsapp://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func addPack(_ args: [String: Any], completion: @escaping (Bool) -> Void) {
        guard
            let packId = args["id"] as? String,
            let name = args["name"] as? String,
            let publisher = args["publisher"] as? String,
            let trayIconPath = args["trayIconPath"] as? String,
            let stickers = args["stickers"] as? [[String: Any]]
        else {
            completion(false)
            return
        }

        var stickerJson: [[String: Any]] = []
        var pasteboardItems: [String: Any] = [:]

        guard let trayData = FileManager.default.contents(atPath: trayIconPath) else {
            completion(false)
            return
        }
        pasteboardItems["tray_\(packId)"] = trayData

        for (index, sticker) in stickers.enumerated() {
            guard let filePath = sticker["filePath"] as? String,
                  let data = FileManager.default.contents(atPath: filePath) else { continue }
            let fileName = "sticker_\(packId)_\(index).webp"
            pasteboardItems[fileName] = data
            stickerJson.append(["image_file_name": fileName, "emojis": []])
        }

        let packJson: [String: Any] = [
            "identifier": packId,
            "name": name,
            "publisher": publisher,
            "tray_image_file_name": "tray_\(packId)",
            "image_data_version": "1",
            "avoid_cache": false,
            "stickers": stickerJson,
        ]
        guard let packData = try? JSONSerialization.data(withJSONObject: packJson) else {
            completion(false)
            return
        }

        var items = pasteboardItems.mapValues { $0 as Any }
        items["sticker_pack"] = packData

        UIPasteboard.general.setItems(
            [items.compactMapValues { $0 as? Data }].map { dict in
                Dictionary(uniqueKeysWithValues: dict.map { ($0.key, $0.value) })
            },
            options: [.expirationDate: Date().addingTimeInterval(60)]
        )

        guard let url = URL(string: "whatsapp://stickerPack") else {
            completion(false)
            return
        }
        UIApplication.shared.open(url) { success in completion(success) }
    }
}
```

Then inside `AppDelegate`'s `application(_:didFinishLaunchingWithOptions:)`, before `return super.application(...)`, register the channel:

```swift
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "sticker_creator/whatsapp", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isWhatsAppInstalled":
        result(WhatsAppStickerExporter.isInstalled())
      case "addPack":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Expected a map", details: nil))
          return
        }
        WhatsAppStickerExporter.addPack(args) { success in
          result(success)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
```

- [ ] **Step 2: Register the URL scheme query in `Info.plist`**

Add, so `canOpenURL`/`open` for `whatsapp://` are permitted:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>whatsapp</string>
</array>
```

- [ ] **Step 3: Manual verification (cannot be automated)**

On a physical iOS device with WhatsApp installed (the pasteboard/URL-scheme handoff doesn't work in the Simulator, which can't run WhatsApp):
1. `flutter run --release`.
2. Create a pack with ≥3 stickers and a tray icon, tap "Add to WhatsApp" (added to the UI in Task 17).
3. Confirm WhatsApp opens and offers to add the pack with the correct tray icon and stickers.

- [ ] **Step 4: Commit**

```bash
git add ios/Runner/AppDelegate.swift ios/Runner/Info.plist
git commit -m "Add iOS WhatsApp handoff (pasteboard + whatsapp://stickerPack)"
```

---

## Task 16: Pack list screen

**Files:**
- Create: `lib/screens/pack_list_screen.dart`
- Create: `lib/widgets/pack_list_tile.dart`

**Interfaces:**
- Consumes: `PackListBloc` (Task 11) via `BlocProvider`/`BlocBuilder`.
- Produces: `class PackListScreen extends StatelessWidget`, `class PackListTile extends StatelessWidget`. Navigates to `PackDetailScreen` (Task 17) on tap, passing the tapped pack's `id`.

- [ ] **Step 1: Write `lib/widgets/pack_list_tile.dart`**

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/sticker_pack.dart';

class PackListTile extends StatelessWidget {
  const PackListTile({super.key, required this.pack, required this.onTap, required this.onDelete});

  final StickerPack pack;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: pack.trayIconPath != null
          ? CircleAvatar(backgroundImage: FileImage(File(pack.trayIconPath!)))
          : const CircleAvatar(child: Icon(Icons.image_outlined)),
      title: Text(pack.name),
      subtitle: Text('${pack.stickers.length} stickers'),
      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 2: Write `lib/screens/pack_list_screen.dart`**

```dart
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
```

- [ ] **Step 3: Commit**

```bash
git add lib/screens/pack_list_screen.dart lib/widgets/pack_list_tile.dart
git commit -m "Add PackListScreen"
```

---

## Task 17: Pack detail screen

**Files:**
- Create: `lib/screens/pack_detail_screen.dart`
- Create: `lib/widgets/sticker_grid_tile.dart`

**Interfaces:**
- Consumes: `PackDetailBloc` (Task 12), `WhatsAppHandoff` (Task 13), navigates to `ImportScreen` (Task 18) to add stickers, uses `image_cropper` directly for the tray icon crop.
- Produces: `class PackDetailScreen extends StatefulWidget` with constructor `PackDetailScreen({required String packId})`.

- [ ] **Step 1: Write `lib/widgets/sticker_grid_tile.dart`**

```dart
import 'dart:io';

import 'package:flutter/material.dart';

class StickerGridTile extends StatelessWidget {
  const StickerGridTile({super.key, required this.filePath, required this.onRemove});

  final String filePath;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: Image.file(File(filePath), fit: BoxFit.cover)),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(radius: 12, child: Icon(Icons.close, size: 16)),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Write `lib/screens/pack_detail_screen.dart`**

```dart
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
    final outputPath = '${cropped.path}_tray.png';
    await context.read<StickerProcessor>().encodeTrayIcon(cropped.path, outputPath);
    if (!context.mounted) return;
    context.read<PackDetailBloc>().add(TrayIconSet(outputPath));
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
                  MaterialPageRoute(builder: (_) => ImportScreen(packId: widget.packId)),
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
```

- [ ] **Step 3: Wrap the "add stickers" navigation with `ImportBloc`**

Replace the FAB's `onPressed` for `heroTag: 'add-sticker'` with:

```dart
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
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/pack_detail_screen.dart lib/widgets/sticker_grid_tile.dart
git commit -m "Add PackDetailScreen with tray icon crop and Add to WhatsApp gate"
```

---

## Task 18: Import screen (direct + link)

**Files:**
- Create: `lib/screens/import_screen.dart`

**Interfaces:**
- Consumes: `ImportBloc` (Task 10), reports back to `PackDetailBloc` (Task 12) via `StickersAdded` on success.
- Produces: `class ImportScreen extends StatefulWidget` with constructor `ImportScreen({required String packId})`.

- [ ] **Step 1: Write `lib/screens/import_screen.dart`**

```dart
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
                    StickersAdded(state.processedFilePaths, StickerType.static_),
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
                        onPressed: () => context.read<ImportBloc>().add(const PickStaticImagesRequested()),
                        child: const Text('Pick images'),
                      ),
                      ElevatedButton(
                        onPressed: () => context.read<ImportBloc>().add(const PickGifRequested()),
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
                          onPressed: () => context.read<ImportBloc>().add(const LinkThumbnailConfirmed()),
                          child: const Text('Use this image'),
                        ),
                      ] else
                        ElevatedButton(
                          onPressed: () => context.read<ImportBloc>().add(LinkUrlSubmitted(_urlController.text.trim())),
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
```

Add `import 'dart:io';` and this helper at the bottom of the file (outside the class), since `Image.file` needs a `File`:

```dart
File _asFile(String path) => File(path);
```

- [ ] **Step 2: Commit**

```bash
git add lib/screens/import_screen.dart
git commit -m "Add ImportScreen (direct pick tabs + paste-URL link import)"
```

---

## Task 19: App shell wiring

**Files:**
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: everything from Tasks 1–18. This is the final assembly — no new production logic, just dependency wiring.

- [ ] **Step 1: Replace `lib/main.dart`**

```dart
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
```

`PackDetailBloc` and `ImportBloc` are created per-navigation in Tasks 16–17 (wrapped in their own `BlocProvider` at the `Navigator.push` call site, reading `PackRepository`/`StickerProcessor` from the `RepositoryProvider`s set up here) — nothing further to wire for them at the app-shell level.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: all tests from Tasks 2–13 PASS.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: no errors. Fix any that surface from wiring mismatches between tasks (e.g. an import path that changed) before proceeding.

- [ ] **Step 4: Manual smoke test**

Run: `flutter run` on an Android or iOS device/emulator. Walk the golden path: create a pack, add 3+ images via direct pick, set a tray icon, confirm "Add to WhatsApp" becomes enabled. Then try the link-import tab with a real TikTok/Instagram/Pinterest URL and confirm the thumbnail preview appears.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "Wire app shell: Hive init, repository providers, pack list as home screen"
```

---

## What's deliberately out of scope (v1)

- Background removal (spec: crop/resize only)
- Emoji tagging per sticker
- Video-file import for animated stickers (ffmpeg_kit_flutter retired; GIF only)
- Any cloud sync/backend/accounts
- iOS share-extension Xcode target automation (manual one-time Xcode setup, noted in Task 9)
