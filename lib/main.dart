import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yaru/yaru.dart';

import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the Yaru client-side window chrome: hides the native GTK
  // title bar so [YaruWindowTitleBar] can be drawn inside the app. On
  // systems where the extension is unavailable this is a no-op and the
  // native title bar stays.
  try {
    await YaruWindowTitleBar.ensureInitialized();
  } catch (_) {
    // Headless / minimal environments: fall back to native window chrome.
  }

  runApp(const UserAssertionEditorApp());
}

class UserAssertionEditorApp extends StatelessWidget {
  const UserAssertionEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Mirrors the system light/dark preference and accent color.
    return YaruTheme(
      builder: (context, yaru, child) {
        return MaterialApp(
          title: 'User Assertion Editor',
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          themeMode: ThemeMode.system,
          debugShowCheckedModeBanner: false,
          // Follow the OS locale so system widgets (e.g. the date picker's
          // manual entry, month names, weekday order) are localized. The
          // global delegates are the whole point of this; and we must widen
          // supportedLocales (it defaults to English-only, which would mask
          // every other language even when the OS is set to one).
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales:
              kMaterialSupportedLanguages.map((lang) => Locale(lang)),
          home: const HomePage(),
        );
      },
    );
  }
}
