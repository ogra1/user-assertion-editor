import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_assertion_editor/models/wizard_state.dart';
import 'package:user_assertion_editor/pages/timing_page.dart';

/// Regression: the date picker's *manual* text-entry format must follow the
/// system locale. This only works if the app ships the global localization
/// delegates AND widens `supportedLocales` — which defaults to English-only
/// and otherwise masks every other language even when the OS is German, etc.
void main() {
  // A helper that renders an [InputDatePickerFormField] (the exact widget the
  // picker's input mode uses) under a given locale and returns the text that
  // was auto-filled for a known date.
  Future<String> filledText(
      WidgetTester tester, Locale locale) async {
    String txt = '';
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Mirror what lib/main.dart does: allow every shipped locale so the
      // requested one is not masked to English.
      supportedLocales:
          kMaterialSupportedLanguages.map((lang) => Locale(lang)),
      home: Builder(builder: (context) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: Material(
            child: SizedBox(
              width: 320,
              height: 60,
              child: InputDatePickerFormField(
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDate: DateTime(2026, 10, 5),
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
    txt =
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    return txt;
  }

  testWidgets('manual date entry is localized for de_DE (day-first, dot sep)',
      (tester) async {
    final txt = await filledText(tester, const Locale('de', 'DE'));
    // German: 5.10.2026 (day.month.year, dot-separated). English would be
    // 10/05/2026 — so this also guards against supportedLocales masking.
    expect(txt, matches(RegExp(r'^\d{1,2}\.\d{1,2}\.\d{4}$')));
    expect(txt, startsWith('5.10'));
  });

  testWidgets('manual date entry stays month-first for en_US (control)',
      (tester) async {
    final txt = await filledText(tester, const Locale('en', 'US'));
    expect(txt, matches(RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$')));
    expect(txt, startsWith('10/5')); // month-first, slash, no zero-pad
  });

  testWidgets('duration line is singular for 1 year and 1 day (regression: "1 years")', (tester) async {
    final state = WizardState();
    final now = DateTime.now().toUtc();
    state.model
      ..since = now
      ..until = now.add(const Duration(days: 365));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TimingPage(state: state)),
    ));
    expect(find.text('Valid for 1 year.'), findsOneWidget);
    expect(find.textContaining('years'), findsNothing);

    // A one-day window must also read singular.
    state.model
      ..since = now
      ..until = now.add(const Duration(days: 1));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TimingPage(state: state)),
    ));
    expect(find.text('Valid for 1 day.'), findsOneWidget);
    state.dispose();
  });
}
