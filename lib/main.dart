import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI style for a premium look
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0F172A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const GemmaTranslatorApp());
}

class GemmaTranslatorApp extends StatelessWidget {
  const GemmaTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemma Offline Translator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: 'sans-serif', // Safe offline fallback
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const SplashScreen(),
    );
  }
}
