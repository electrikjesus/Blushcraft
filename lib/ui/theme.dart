import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Warm blush palette: rose / cream / charcoal (not purple-gradient default).
class BlushTheme {
  static const rose = Color(0xFFC45C6A);
  static const roseDeep = Color(0xFF9E3D4A);
  static const cream = Color(0xFFFAF3F0);
  static const creamDark = Color(0xFFF0E0DA);
  static const blush = Color(0xFFE8A0A8);
  static const charcoal = Color(0xFF2C2426);
  static const inkMuted = Color(0xFF6B5A5E);
  static const cardFace = Color(0xFFFFFBFA);
  static const statementFace = Color(0xFF2C2426);
  static const choiceAccent = Color(0xFFD47884);

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: rose,
        onPrimary: Colors.white,
        secondary: blush,
        onSecondary: charcoal,
        surface: cream,
        onSurface: charcoal,
        error: roseDeep,
      ),
      scaffoldBackgroundColor: cream,
    );

    return base.copyWith(
      textTheme: GoogleFonts.sourceSans3TextTheme(base.textTheme).apply(
        bodyColor: charcoal,
        displayColor: charcoal,
      ),
      primaryTextTheme:
          GoogleFonts.frauncesTextTheme(base.primaryTextTheme).apply(
        bodyColor: charcoal,
        displayColor: charcoal,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: charcoal,
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: charcoal,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: rose,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.sourceSans3(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: roseDeep,
          side: const BorderSide(color: rose, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardFace,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: creamDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: rose, width: 2),
        ),
      ),
    );
  }

  static TextStyle display(double size, {FontWeight? weight, Color? color}) {
    return GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w600,
      color: color ?? charcoal,
      height: 1.15,
    );
  }

  static TextStyle body(double size, {FontWeight? weight, Color? color}) {
    return GoogleFonts.sourceSans3(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? charcoal,
      height: 1.35,
    );
  }
}

/// Soft atmospheric background: cream with a rose wash.
class BlushBackdrop extends StatelessWidget {
  const BlushBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF8F6),
            Color(0xFFFAE8E6),
            Color(0xFFF5D6D8),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}
