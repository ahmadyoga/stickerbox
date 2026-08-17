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
