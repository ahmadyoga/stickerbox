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
