import 'dart:async';

import 'package:flutter/material.dart';
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
          home: const HomePage(),
        );
      },
    );
  }
}
