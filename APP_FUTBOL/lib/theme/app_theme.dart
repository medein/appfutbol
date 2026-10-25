import 'package:flutter/material.dart';

/// Paleta y estilos centrales de la app.
/// Todas las pantallas leen de aquí para verse consistentes.
class AppColors {
  // Verde cancha, más profundo y elegante que el Colors.green plano
  static const Color primary = Color(0xFF0E9F6E);
  static const Color primaryDark = Color(0xFF057A55);
  static const Color primaryLight = Color(0xFF31C48D);
  static const Color accent = Color(0xFFFFB020);

  static const Color ink = Color(0xFF111827);
  static const Color inkSoft = Color(0xFF4B5563);
  static const Color inkMuted = Color(0xFF9CA3AF);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF4F6F8);
  static const Color border = Color(0xFFE5E7EB);

  static const Color success = Color(0xFF0E9F6E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE02424);
  static const Color info = Color(0xFF3F83F8);

  /// Degradado principal usado en encabezados y tarjetas destacadas.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF057A55), Color(0xFF0E9F6E), Color(0xFF31C48D)],
  );
}

class AppRadius {
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;
}

class AppShadows {
  static List<BoxShadow> get soft => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get lifted => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.primaryLight,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.adaptivePlatformDensity,

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        bodyLarge: TextStyle(fontSize: 15, color: AppColors.ink, height: 1.4),
        bodyMedium: TextStyle(fontSize: 14, color: AppColors.inkSoft, height: 1.4),
        bodySmall: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),

      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.inkMuted,
          elevation: 0,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(0, 52),
          side: const BorderSide(color: AppColors.border, width: 1.4),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
        labelStyle: const TextStyle(color: AppColors.inkSoft, fontSize: 14),
        prefixIconColor: AppColors.inkSoft,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.8),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.background,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 24,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        contentTextStyle: const TextStyle(fontSize: 14.5, color: AppColors.inkSoft, height: 1.45),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.primaryDark
                : AppColors.inkSoft,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.primaryDark
                : AppColors.inkSoft,
          ),
        ),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkSoft,
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        subtitleTextStyle: TextStyle(fontSize: 13, color: AppColors.inkSoft),
      ),
    );
  }
}
