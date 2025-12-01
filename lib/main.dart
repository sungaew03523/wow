
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryTextColor = Color(0xFFD4BF7A);
    const Color darkBackgroundColor = Color(0xFF1A1A1A);
    const Color panelBackgroundColor = Color(0xFF211F1F);

    final wowTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackgroundColor,
      textTheme: GoogleFonts.latoTextTheme(ThemeData.dark().textTheme).copyWith(
        bodyLarge: const TextStyle(color: primaryTextColor, fontSize: 16),
        titleMedium: const TextStyle(
          color: primaryTextColor,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.grey),
      ),
      cardColor: panelBackgroundColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: panelBackgroundColor,
        elevation: 0,
        toolbarHeight: 65,
        shape: Border(bottom: BorderSide(color: Colors.black, width: 2)),
      ),
      iconTheme: const IconThemeData(color: primaryTextColor, size: 20),
    );

    return MaterialApp.router(
      title: 'WoW Item Browser',
      theme: wowTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: router, // Используем роутер из app_router.dart
    );
  }
}
