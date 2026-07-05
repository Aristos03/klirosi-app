import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const KlirosiApp());
}

class KlirosiApp extends StatelessWidget {
  const KlirosiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // A black-and-gold "VIP raffle" palette: warm metallic gold as the
    // primary accent, a deep wine/burgundy secondary for contrast, and a
    // true near-black surface instead of Material's usual warm dark grey.
    const gold = Color(0xFFD9B44A);
    final scheme = ColorScheme.fromSeed(
      seedColor: gold,
      brightness: Brightness.dark,
    ).copyWith(
      primary: gold,
      onPrimary: Colors.black,
      primaryContainer: const Color(0xFF8A6A1F),
      onPrimaryContainer: Colors.white,
      secondary: const Color(0xFF8A2C3B),
      onSecondary: Colors.white,
      surface: const Color(0xFF111013),
      onSurface: Colors.white,
      surfaceContainerHigh: const Color(0xFF1C1A1E),
      surfaceContainerHighest: const Color(0xFF262327),
      outline: const Color(0xFF8F8A82),
    );

    return MaterialApp(
      title: 'Κλήρωση Λαχείων',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      home: const HomeScreen(),
    );
  }
}
