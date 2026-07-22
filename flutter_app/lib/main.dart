import 'package:flutter/material.dart';

import 'screens/scanner_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_settings_service.dart';
import 'utils/app_constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load any previously saved Snipe-IT connection settings (Server URL/IP
  // + API Token) from on-device storage. These are no longer baked in at
  // build time via `.env` — they're entered and saved from the in-app
  // Settings screen instead, so switching servers or rotating the token
  // never requires a new build.
  await AppSettingsService.init();

  runApp(const SnipeITApp());
}

class SnipeITApp extends StatelessWidget {
  const SnipeITApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IT Asset Scanner',
      debugShowCheckedModeBanner: false,
      theme: AppConstants.theme,
      routes: {
        '/scanner': (_) => const ScannerScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
      // First run (no saved URL/token yet) lands on Settings so the user
      // configures the connection before anything tries to call the API.
      // Once configured, subsequent launches go straight to the scanner.
      home: AppSettingsService.isConfigured
          ? const ScannerScreen()
          : const SettingsScreen(isInitialSetup: true),
    );
  }
}