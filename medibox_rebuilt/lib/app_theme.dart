import 'package:flutter/material.dart';

abstract final class AppPalette {
  static const background = Color(0xffeef2eb);
  static const surface = Color(0xfffbfdfb);
  static const surfaceMuted = Color(0xfff1f5f1);
  static const primary = Color(0xff2f6f3e);
  static const accent = Color(0xff3fbd50);
  static const primarySoft = Color(0xffe3f5e7);
  static const text = Color(0xff101713);
  static const textMuted = Color(0xff667085);
  static const border = Color(0xffcbd5cd);
  static const warning = Color(0xffa76300);
  static const warningSoft = Color(0xfffff1d6);
  static const danger = Color(0xffc43d43);
  static const dangerSoft = Color(0xffffe8e9);
  static const info = Color(0xff287bb5);
  static const infoSoft = Color(0xffe6f4ff);
}

ThemeData buildMediBoxTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppPalette.primary,
    primary: AppPalette.primary,
    surface: AppPalette.surface,
    error: AppPalette.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: AppPalette.background,
    textTheme: base.textTheme.copyWith(
      headlineLarge: const TextStyle(
        color: AppPalette.text,
        fontSize: 38,
        height: 1.2,
        fontWeight: FontWeight.w900,
      ),
      headlineMedium: const TextStyle(
        color: AppPalette.text,
        fontSize: 30,
        height: 1.25,
        fontWeight: FontWeight.w900,
      ),
      titleLarge: const TextStyle(
        color: AppPalette.text,
        fontSize: 24,
        height: 1.3,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: const TextStyle(
        color: AppPalette.text,
        fontSize: 19,
        height: 1.35,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: const TextStyle(
        color: AppPalette.text,
        fontSize: 18,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        color: AppPalette.text,
        fontSize: 16,
        height: 1.4,
      ),
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: AppPalette.background,
      foregroundColor: AppPalette.text,
      titleTextStyle: TextStyle(
        color: AppPalette.text,
        fontSize: 26,
        fontWeight: FontWeight.w900,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppPalette.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppPalette.border, width: 1.4),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 18,
      backgroundColor: AppPalette.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      titleTextStyle: const TextStyle(
        color: AppPalette.text,
        fontSize: 28,
        fontWeight: FontWeight.w900,
      ),
      contentTextStyle: const TextStyle(
        color: AppPalette.text,
        fontSize: 17,
        height: 1.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(120, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        backgroundColor: AppPalette.primary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(110, 52),
        padding: const EdgeInsets.symmetric(horizontal: 21, vertical: 14),
        foregroundColor: AppPalette.primary,
        side: const BorderSide(color: AppPalette.primary, width: 1.5),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(88, 48),
        foregroundColor: AppPalette.primary,
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      labelStyle: const TextStyle(color: AppPalette.textMuted, fontSize: 17),
      hintStyle: const TextStyle(color: AppPalette.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: AppPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: AppPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: AppPalette.primary, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppPalette.text,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 17),
    ),
    dividerTheme: const DividerThemeData(color: AppPalette.border),
  );
}

BoxDecoration appPanelDecoration({Color color = AppPalette.surface}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: AppPalette.border, width: 1.5),
      boxShadow: const [
        BoxShadow(
          color: Color(0x150b3520),
          blurRadius: 22,
          offset: Offset(0, 9),
        ),
      ],
    );

class AppPageCard extends StatelessWidget {
  const AppPageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(30),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: appPanelDecoration(),
    child: child,
  );
}
