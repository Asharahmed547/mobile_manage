import 'package:flutter/material.dart';

const shopName = 'First Choice Mobile';
const kPrimary = Color(0xFF4338CA);
const kAccent = Color(0xFF06B6D4);

const kGradient = LinearGradient(
  colors: [Color(0xFF312E81), Color(0xFF4338CA), Color(0xFF0891B2)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

String rs(num v) {
  final s = v.round().toString();
  final withCommas =
      s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return 'Rs $withCommas';
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kPrimary);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF4F5FB),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimary, width: 1.6),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
  );
}