import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/system_user_model.dart';
import 'assertion_builder.dart';

class SignException implements Exception {
  final String message;
  const SignException(this.message);
  @override
  String toString() => message;
}

class SignResult {
  final String signedChain;
  final String jsonHeader;
  const SignResult({required this.signedChain, required this.jsonHeader});
}

/// Signs a system-user assertion with `snap sign -k <key> --chain`,
/// feeding the JSON header on stdin. The `--chain` flag appends the
/// account-key and account assertions, producing a ready-to-use
/// `auto-import.assert`.
class SignService {
  final String snapExecutable;

  const SignService({this.snapExecutable = 'snap'});

  Future<SignResult> sign(SystemUser user, String keyName,
      {Duration timeout = const Duration(minutes: 2)}) async {
    if (keyName.trim().isEmpty) {
      throw const SignException('No signing key selected.');
    }

    final jsonHeader = AssertionBuilder.buildJson(user);

    final Process process;
    try {
      process = await Process.start(
        snapExecutable,
        ['sign', '-k', keyName, '--chain'],
      );
    } on ProcessException catch (e) {
      throw SignException(
          'Could not run "snap sign". Is snapd installed?\n${e.message}');
    }

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    process.stdin.write(jsonHeader);
    await process.stdin.flush();
    await process.stdin.close();

    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      throw const SignException(
        'Signing timed out. If your key has a passphrase, "snap sign" may '
        'be waiting for input it cannot prompt for here. Use a key without '
        'a passphrase, or ensure a graphical pinentry is available.',
      );
    }

    final signed = await stdoutFuture;
    final errText = await stderrFuture;

    if (exitCode != 0) {
      throw SignException(_friendlyError(errText, signed, keyName));
    }
    if (signed.trim().isEmpty) {
      throw SignException('snap sign produced no output.\n$errText');
    }
    return SignResult(signedChain: signed, jsonHeader: jsonHeader);
  }

  /// Turns snapd's terse (or panic-level) output into an actionable
  /// message.
  String _friendlyError(String stderr, String stdout, String keyName) {
    final text = (stderr.trim().isNotEmpty ? stderr : stdout).trim();
    if (text.contains('no assertion found for account-key')) {
      return 'The key "$keyName" is not registered with the Snap Store '
          '(no account-key assertion found for it). Register it first: '
          'snap export-key $keyName <account-id>';
    }
    if (text.contains('cannot use') && text.contains('key')) {
      return 'The key "$keyName" could not be loaded. '
          'Check the keyring: snap keys';
    }
    if (text.contains('unexpected value type copying headers') ||
        text.contains('panic: internal error')) {
      return 'snapd crashed while processing the assertion (older snapd '
          'releases panic on some header encodings). Update snapd and try '
          'again: sudo snap refresh snapd';
    }
    return 'Signing failed (snap sign exited with an error).';
  }
}
