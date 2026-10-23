import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';

import 'package:user_assertion_editor/models/system_user_model.dart';
import 'package:user_assertion_editor/models/wizard_state.dart';
import 'package:user_assertion_editor/models/wizard_step.dart';
import 'package:user_assertion_editor/pages/home_page.dart';
import 'package:user_assertion_editor/widgets/tag_chip_field.dart';
import 'package:user_assertion_editor/services/assertion_builder.dart';
import 'package:user_assertion_editor/services/assertion_parser.dart';
import 'package:user_assertion_editor/services/assertion_verifier.dart';

SystemUser _ssoUser() => SystemUser.defaults()
  ..username = 'admin'
  ..email = 'admin@example.com'
  ..sshKeys.add('ssh-ed25519 AAAAC3Nza user@host')
  ..brandId = 'mybrand'
  ..authorityId = 'mybrand'
  ..models.add('pc-amd64');

void main() {
  testWidgets('TagChipField keeps the draft local until Enter or comma (regression: no per-keystroke chips)', (tester) async {
    final entered = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TagChipField(
          label: 'Models',
          values: entered,
          // Contract: onChanged receives the NEW full list -> replace.
          onChanged: (l) => entered
            ..clear()
            ..addAll(l),
        ),
      ),
    ));

    // Type a whole word: nothing is committed per keystroke.
    await tester.enterText(find.byType(TextField), 'pc-amd64');
    await tester.pump();
    expect(entered, isEmpty, reason: 'draft must not commit on keystrokes');

    // Enter commits exactly one chip.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(entered, ['pc-amd64']);

    // Comma commits the left part, keeps the right part as draft.
    // (enterText appends to the current value, so reset the draft first.)
    final tf = find.byType(TextField);
    tester.widget<TextField>(tf).controller!.text = '';
    await tester.enterText(tf, 'other,third');
    await tester.pump();
    expect(entered, ['pc-amd64', 'other']);
    final draft =
        tester.widget<TextField>(find.byType(TextField)).controller!.text;
    expect(draft, 'third');
  });

  test('signing key step completes on key selection; export is then reachable (regression: no sign-before-export deadlock)', () {
    final state = WizardState();
    // Complete User/Device/Timing prerequisites.
    state.model
      ..username = 'admin'
      ..email = 'admin@example.com'
      ..brandId = 'mybrand'
      ..authorityId = 'mybrand'
      ..models.add('pc-amd64')
      ..sshKeys.add('ssh-ed25519 AAAA x@y');

    // No key yet: sign step incomplete, export locked.
    expect(state.isStepComplete(WizardStep.sign), isFalse);
    expect(state.isStepEnabled(WizardStep.export), isFalse);

    // Pick a key: sign step complete and export reachable WITHOUT signing.
    state.selectedKeyName = 'my-brand-key';
    expect(state.errorsFor(WizardStep.sign), isEmpty);
    expect(state.isStepComplete(WizardStep.sign), isTrue);
    expect(state.isStepEnabled(WizardStep.export), isTrue);
  });


  testWidgets('home page renders the User step by default', (tester) async {
    await tester.pumpWidget(YaruTheme(
      builder: (context, yaru, child) => MaterialApp(
        theme: yaru.theme,
        darkTheme: yaru.darkTheme,
        home: const HomePage(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Username *'), findsOneWidget);
    expect(find.text('Brand ID *'), findsNothing);
    expect(find.text('Signing Key'), findsOneWidget); // nav rail destination
  });

  test('defaults produce an SSO-style (SSH, no password) header', () {
    final u = _ssoUser();
    final parsed = AssertionParser.parseOne(AssertionBuilder.buildJson(u));
    expect(parsed.headers['type'], 'system-user');
    // "format" must be the STRING "2": a JSON number makes `snap sign`
    // panic (copyHeader only takes string/list/map), and omitting it
    // defaults to 0, which rejects serials (>=1) and user-presence (>=2).
    expect(parsed.headers['format'], '2');
    expect(parsed.headers['username'], 'admin');
    expect(parsed.headers['models'], ['pc-amd64']);
    expect(parsed.headers.containsKey('password'), isFalse);
    expect(parsed.headers['since'], endsWith('Z'));
    expect(parsed.headers['until'], endsWith('Z'));
  });

  test('password + force-change + user-presence land in the header', () {
    final u = _ssoUser()
      ..passwordHash = r'$6$salt$abcdefghijklmnopqrstuv'
      ..forcePasswordChange = true
      ..userUntilExpiration = true;
    final parsed = AssertionParser.parseOne(AssertionBuilder.buildJson(u));
    expect(parsed.headers['password'], startsWith(r'$6$'));
    expect(parsed.headers['force-password-change'], true);
    expect(parsed.headers['user-presence'], 'until-expiration');
  });

  test('global assertion (no models) is limited to 365 days', () {
    final u = _ssoUser()..models.clear();
    u.until = u.since!.add(const Duration(days: 366));
    expect(
        AssertionValidation.timingErrors(u)
            .any((e) => e.contains('365')),
        isTrue);
  });

  test('serials require exactly one model', () {
    final u = _ssoUser()
      ..models.add('m2')
      ..serials.add('serial1');
    expect(
        AssertionValidation.deviceErrors(u)
            .any((e) => e.contains('exactly one model')),
        isTrue);
  });

  test('user errors: empty auth and bad username', () {
    final u = _ssoUser()
      ..sshKeys.clear()
      ..passwordHash = null
      ..username = 'Bad_User';
    final errors = AssertionValidation.userErrors(u);
    expect(errors.any((e) => e.contains('Username')), isTrue);
    expect(errors.any((e) => e.contains('SSH key or a password')), isTrue);
  });

  test('parser round-trips a signed chain (3 assertions)', () {
    final fakeSig = 'A' * 120;
    final chain = [
      'type: system-user\nauthority-id: mybrand\nbrand-id: mybrand\n'
          'email: admin@example.com\nusername: admin\nseries:\n  - ubuntu\n'
          'models:\n  - pc-amd64\n\n$fakeSig',
      'type: account-key\naccount-id: mybrand\n'
          'public-key-sha3-384: abc\n\n$fakeSig',
      'type: account\naccount-id: mybrand\n\n$fakeSig',
    ].join('\n\n');
    final parsed = AssertionParser.parseChain(chain);
    expect(parsed.length, 3);
    expect(
        parsed.map((p) => p.headers['type']).toList(),
        ['system-user', 'account-key', 'account']);
    expect(parsed.first.headers['username'], 'admin');
    expect(parsed.first.headers['models'], ['pc-amd64']);
  });

  test('verification report flags a wrong username', () async {
    final u = _ssoUser();
    // The signed assertion contains 'other', but the model has 'admin'.
    final chain = 'type: system-user\nauthority-id: mybrand\n'
        'brand-id: mybrand\nemail: admin@example.com\nusername: other\n'
        'since: ${u.since!.toIso8601String()}\n'
        'until: ${u.until!.toIso8601String()}\n'
        'sign-key-sha3-384: '
        'kKdkgxTJSRwm5OT5MgVxo4zv0Y19AAloJE4dq7C0QlbPsdbof0G5g0lCpg0J_\n\n'
        '${'A' * 120}';
    final report = await AssertionVerifier().verify(
      signedChain: chain,
      user: u,
      keyName: 'testkey',
    );
    expect(report.allPassed, isFalse);
    expect(
        report.checks
            .any((c) => c.label == 'Username' && c.status == CheckStatus.fail),
        isTrue);
  });
}
