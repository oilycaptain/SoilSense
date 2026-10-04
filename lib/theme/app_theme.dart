import 'package:flutter/material.dart';


class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class AppTheme {
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color accentGreen = Color(0xFF81C784);
  static const Color warningRed = Color(0xFFE53935);
  static const Color warningOrange = Color(0xFFFFB300);
  static const Color cardBackground = Color(0xFFF5F9F5);
  static const Color textDark = Color(0xFF1A2E1A);
  static const Color textLight = Color(0xFF5A7A5A);
  static const Color white = Color(0xFFFFFFFF);
  static const Color shadowColor = Color(0x1A2E7D32);

  static ThemeData lightTheme = ThemeData(
    fontFamily: 'Inter',
    brightness: Brightness.light,
    primaryColor: primaryGreen,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _NoTransitionsBuilder(),
        TargetPlatform.iOS: _NoTransitionsBuilder(),
        TargetPlatform.windows: _NoTransitionsBuilder(),
        TargetPlatform.macOS: _NoTransitionsBuilder(),
        TargetPlatform.linux: _NoTransitionsBuilder(),
        TargetPlatform.fuchsia: _NoTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: const Color(0xFFF0F5F0),
    colorScheme: const ColorScheme.light(
      primary: primaryGreen,
      secondary: primaryLight,
      surface: white,
      onSurface: textDark,
      onSurfaceVariant: textLight,
      error: warningRed,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: primaryGreen),
      titleTextStyle: TextStyle(
        color: textDark,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    cardTheme: CardThemeData(
      color: white,
      elevation: 2,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryGreen, width: 2),
      ),
      hintStyle: const TextStyle(color: textLight),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textDark),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: textDark),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textDark),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textDark),
      bodyLarge: TextStyle(fontSize: 16, color: textDark),
      bodyMedium: TextStyle(fontSize: 14, color: textLight),
      bodySmall: TextStyle(fontSize: 12, color: textLight),
    ),
  );

  /// A forest-toned dark appearance. Existing SoilSense result cards keep a
  /// soft sage surface so sensor colors and threshold labels stay readable.
  static ThemeData darkTheme = ThemeData(
    fontFamily: 'Inter',
    brightness: Brightness.dark,
    primaryColor: accentGreen,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _NoTransitionsBuilder(),
        TargetPlatform.iOS: _NoTransitionsBuilder(),
        TargetPlatform.windows: _NoTransitionsBuilder(),
        TargetPlatform.macOS: _NoTransitionsBuilder(),
        TargetPlatform.linux: _NoTransitionsBuilder(),
        TargetPlatform.fuchsia: _NoTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: const Color(0xFF101712),
    colorScheme: const ColorScheme.dark(
      primary: accentGreen,
      secondary: primaryLight,
      surface: Color(0xFF1A261D),
      onSurface: Color(0xFFF1F6F2),
      onSurfaceVariant: Color(0xFFC5D4C8),
      outline: Color(0xFF6C8170),
      outlineVariant: Color(0xFF34473A),
      error: Color(0xFFFF7A73),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF141E16),
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: accentGreen),
      titleTextStyle: TextStyle(
        color: Color(0xFFF1F6F2),
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF141E16),
      selectedItemColor: accentGreen,
      unselectedItemColor: Color(0xFFB1C4B5),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A261D),
      elevation: 1,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2B3B2F)),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF1A261D),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1A261D),
      modalBackgroundColor: Color(0xFF1A261D),
    ),
    dividerColor: const Color(0xFF3B4D40),
    iconTheme: const IconThemeData(color: Color(0xFFC5D4C8)),
    listTileTheme: const ListTileThemeData(
      textColor: Color(0xFFF1F6F2),
      iconColor: Color(0xFF81C784),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFF223026),
      selectedColor: const Color(0xFF29452F),
      labelStyle: const TextStyle(color: Color(0xFFF1F6F2)),
      side: const BorderSide(color: Color(0xFF3B4D40)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF26362A),
      contentTextStyle: TextStyle(color: Color(0xFFF1F6F2)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryGreen,
        foregroundColor: white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF223026),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF314436)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentGreen, width: 2),
      ),
      hintStyle: const TextStyle(color: Color(0xFFB1C4B5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFF1F6F2)),
      headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Color(0xFFF1F6F2)),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF1F6F2)),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xFFF1F6F2)),
      bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFF1F6F2)),
      bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFC5D4C8)),
      bodySmall: TextStyle(fontSize: 12, color: Color(0xFFB1C4B5)),
    ),
  );
}
