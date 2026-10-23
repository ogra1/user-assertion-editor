import 'dart:convert';
import 'dart:io';

/// A signing key available locally to `snap sign`.
class SigningKey {
  final String name;
  final String sha3384;

  const SigningKey({required this.name, required this.sha3384});

  @override
  String toString() => name;
}

class KeyException implements Exception {
  final String message;
  const KeyException(this.message);
  @override
  String toString() => message;
}

/// Lists the local snapd signing keyring via `snap keys` (hidden command,
/// JSON output), the same keys `snap sign -k <name>` accepts.
class SigningKeyService {
  final String snapExecutable;

  const SigningKeyService({this.snapExecutable = 'snap'});

  Future<List<SigningKey>> listKeys() async {
    final ProcessResult result;
    try {
      result = await Process.run(
        snapExecutable,
        const ['keys', '--json'],
        runInShell: false,
      ).timeout(const Duration(seconds: 20));
    } on ProcessException catch (_) {
      throw const KeyException(
        'Could not run "snap keys". Is snapd installed and working?',
      );
    }
    if (result.exitCode != 0) {
      throw KeyException(
          'snap keys failed: ${_oneLine(result.stderr)}');
    }
    try {
      final decoded = jsonDecode(result.stdout as String);
      final list = (decoded is List) ? decoded : const [];
      return list
          .whereType<Map>()
          .map((m) => SigningKey(
                name: m['name'] as String? ?? '',
                sha3384: m['sha3-384'] as String? ?? '',
              ))
          .where((k) => k.name.isNotEmpty)
          .toList();
    } on FormatException catch (e) {
      throw KeyException('Could not parse "snap keys" output: ${e.message}');
    }
  }

  static String _oneLine(Object? o) =>
      (o as String? ?? '').trim().split('\n').first;
}
