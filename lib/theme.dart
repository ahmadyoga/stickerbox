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
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.line, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.line, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: colors.acc, width: 1.5),
      ),
    ),
    extensions: [colors],
  );
}
