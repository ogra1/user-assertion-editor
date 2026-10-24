import 'dart:convert';

import '../models/system_user_model.dart';
import 'assertion_parser.dart';

class ImportException implements Exception {
  final String message;
  const ImportException(this.message);
  @override
  String toString() => message;
}

/// Loads an existing assertion (signed text chain or JSON header) into the
/// editor so it can be tweaked and re-signed.
class ImportService {
  /// Returns the model populated from [text]. [signed] is the raw text of
  /// the main assertion (for display); null for pure JSON input.
  ({SystemUser user, String? signedMain}) import(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const ImportException('File is empty.');
    }

    if (trimmed.startsWith('{')) {
      final u = _fromJson(trimmed);
      return (user: u, signedMain: null);
    }

    final chain = AssertionParser.parseChain(trimmed);
    final main = chain.firstWhere(
      (a) => a['type'] == 'system-user',
      orElse: () => throw const ImportException(
          'No "system-user" assertion found in the file.'),
    );
    final u = _fromHeaders(main.headers);
    return (user: u, signedMain: main.raw);
  }

  SystemUser _fromJson(String text) {
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw ImportException('Invalid JSON: ${e.message}');
    }
    if (decoded is! Map) {
      throw const ImportException('JSON root must be an object.');
    }
    final headers = <String, dynamic>{
      for (final e in decoded.entries) e.key as String: e.value,
    };
    if (headers['type'] == null) headers['type'] = 'system-user';
    return _fromHeaders(headers);
  }

  SystemUser _fromHeaders(Map<String, dynamic> h) {
    final u = SystemUser();
    void str(String key) {
      final v = h[key];
      if (v is String && v.isNotEmpty) {
        switch (key) {
          case 'email':
            u.email = v;
          case 'brand-id':
            u.brandId = v;
          case 'authority-id':
            u.authorityId = v;
          case 'name':
            u.name = v;
          case 'username':
            u.username = v;
          case 'password':
            u.passwordHash = v;
          case 'since':
            u.since = _parseDate(v);
          case 'until':
            u.until = _parseDate(v);
          // 'series' is intentionally ignored: the editor always emits the
          // fixed series "16" (see AssertionBuilder).
          default:
        }
      }
    }

    str('email');
    str('brand-id');
    str('authority-id');
    str('name');
    str('username');
    str('password');
    str('since');
    str('until');
    if (h['models'] is List) {
      u.models
        ..clear()
        ..addAll((h['models'] as List).map((e) => e.toString()));
    }
    if (h['serials'] is List) {
      u.serials
        ..clear()
        ..addAll((h['serials'] as List).map((e) => e.toString()));
    }
    if (h['ssh-keys'] is List) {
      u.sshKeys
        ..clear()
        ..addAll((h['ssh-keys'] as List).map((e) => e.toString()));
    }
    if (h['force-password-change'] == true) u.forcePasswordChange = true;
    if (h['user-presence'] == 'until-expiration') u.userUntilExpiration = true;
    return u;
  }

  DateTime? _parseDate(String v) => DateTime.tryParse(v)?.toUtc();
}
