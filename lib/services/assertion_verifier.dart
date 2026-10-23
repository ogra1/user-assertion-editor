import '../models/system_user_model.dart';
import 'assertion_builder.dart';
import 'assertion_parser.dart';

enum CheckStatus { pass, warn, fail }

class VerificationCheck {
  final String label;
  final CheckStatus status;
  final String detail;
  const VerificationCheck(this.label, this.status, this.detail);
}

class VerificationReport {
  final List<VerificationCheck> checks;
  const VerificationReport(this.checks);

  bool get allPassed => checks.every((c) => c.status != CheckStatus.fail);
  bool get hasWarnings => checks.any((c) => c.status == CheckStatus.warn);
}

/// Cross-checks a signed chain against the form that was signed, so the
/// user sees exactly what they are about to ship.
class AssertionVerifier {
  Future<VerificationReport> verify({
    required String signedChain,
    required SystemUser user,
    required String keyName,
  }) async {
    final checks = <VerificationCheck>[];

    final List<ParsedAssertion> parsed;
    try {
      parsed = AssertionParser.parseChain(signedChain);
      checks.add(const VerificationCheck(
          'Structure', CheckStatus.pass, 'Chain parsed successfully.'));
    } on AssertionError catch (e) {
      checks.add(VerificationCheck('Structure', CheckStatus.fail, e.toString()));
      return VerificationReport(checks);
    } on Exception catch (e) {
      checks.add(VerificationCheck('Structure', CheckStatus.fail, e.toString()));
      return VerificationReport(checks);
    }

    final main = parsed.first;
    if (main.headers.length + parsed.length < parsed.length + 1) {} // no-op
    if (main['type'] != 'system-user') {
      checks.add(VerificationCheck('Type', CheckStatus.fail,
          'First assertion is "${main['type']}", expected "system-user".'));
    } else {
      checks.add(const VerificationCheck(
          'Type', CheckStatus.pass, 'system-user'));
    }

    if (parsed.length == 3) {
      checks.add(const VerificationCheck(
          'Chain',
          CheckStatus.pass,
          'system-user + account-key + account (ready for auto-import.assert).'));
    } else {
      checks.add(VerificationCheck(
          'Chain',
          CheckStatus.warn,
          'Expected 3 assertions in the chain, found ${parsed.length}.'));
    }

    // Compare against what we signed.
    final expected =
        AssertionParser.parseOne(AssertionBuilder.buildJson(user)).headers;
    _checkEqual(checks, 'Username', expected['username'], main['username']);
    _checkEqual(checks, 'E-mail', expected['email'], main['email']);
    _checkEqual(checks, 'Brand ID', expected['brand-id'], main['brand-id']);
    _checkEqual(checks, 'Authority ID',
        expected['authority-id'], main['authority-id']);
    _checkEqual(checks, 'Password hash', expected['password'], main['password']);
    _checkEqual(checks, 'Since', expected['since'], main['since']);
    _checkEqual(checks, 'Until', expected['until'], main['until']);

    final models = expected['models'];
    if (models is List) {
      final actual = main.headers['models'];
      final same = actual is List &&
          actual.length == models.length &&
          List.generate(
                  models.length, (i) => actual[i].toString() == models[i].toString())
              .every((b) => b);
      if (same) {
        checks.add(
            VerificationCheck('Models', CheckStatus.pass, models.join(', ')));
      } else {
        checks.add(VerificationCheck('Models', CheckStatus.fail,
            'Expected [${models.join(', ')}], got $actual.'));
      }
    }

    final sig = main.signature;
    if (sig.length < 32) {
      checks.add(VerificationCheck('Signature', CheckStatus.fail,
          'Signature block is suspiciously short.'));
    } else {
      checks.add(VerificationCheck(
          'Signature', CheckStatus.pass, 'Present (${sig.length} chars).'));
    }
    final signKey = main['sign-key-sha3-384'];
    if (signKey == null) {
      checks.add(VerificationCheck('Signing key', CheckStatus.fail,
          'No sign-key-sha3-384 header.'));
    } else {
      checks.add(VerificationCheck('Signing key', CheckStatus.pass,
          'Signed with $keyName (${signKey.substring(0, 12)}\u2026)'));
    }
    return VerificationReport(checks);
  }

  void _checkEqual(
      List<VerificationCheck> checks, String label, Object? expected, Object? actual) {
    if (expected == null) return; // field was omitted by design
    if ('$expected' == '$actual') {
      checks.add(VerificationCheck(label, CheckStatus.pass, '$actual'));
    } else {
      checks.add(VerificationCheck(label, CheckStatus.fail,
          'Expected "$expected" but assertion contains "$actual".'));
    }
  }
}
