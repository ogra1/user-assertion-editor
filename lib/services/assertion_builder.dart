import 'dart:convert';

import '../models/system_user_model.dart';

/// Builds the JSON header passed to `snap sign` for a system-user
/// assertion, following the documented field rules:
///
/// /// * `series` is always a list (assertion format 2);
/// * `models` / `serials` are lists and omitted when empty;
/// * `since` / `until` are RFC 3339 UTC;
/// * `password` must already be a crypt(3) hash (see [PasswordHasher]).
class AssertionBuilder {
  static String buildJson(SystemUser u) {
    // "format" is ALWAYS 2 (the system-user max) and is emitted as a
    // STRING: snapd's header copier (asserts/headers.go copyHeader) only
    // accepts string/[]any/map, so a JSON *number* makes `snap sign` panic.
    // Omitting it is not an option either — snapd then defaults to format 0,
    // which rejects the optional "serials" (needs >=1) and
    // "user-presence" (needs >=2) headers. "2" is valid in every case.
    final h = <String, dynamic>{
      'type': 'system-user',
      'format': '2',
      'authority-id': u.authorityId.trim(),
      'brand-id': u.brandId.trim(),
      // Series is fixed at "16": it has not changed since snapd existed and
      // is the only current series. No user input — re-add a field here only
      // if snapd ever ships another series.
      'series': ['16'],
      'email': u.email.trim(),
    };

    if (u.name.trim().isNotEmpty) h['name'] = u.name.trim();
    h['username'] = u.username.trim();

    if (u.hasPassword) h['password'] = u.passwordHash;
    if (u.forcePasswordChange) h['force-password-change'] = true;
    if (u.hasSshKeys) {
      h['ssh-keys'] =
          u.sshKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    }

    final models = u.models.map((m) => m.trim()).where((m) => m.isNotEmpty);
    final modelList = models.toList();
    if (modelList.isNotEmpty) h['models'] = modelList;

    final serials =
        u.serials.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (serials.isNotEmpty) h['serials'] = serials;

    if (u.since != null) h['since'] = SystemUser.rfc3339(u.since!);
    if (u.until != null) h['until'] = SystemUser.rfc3339(u.until!);
    if (u.userUntilExpiration) h['user-presence'] = 'until-expiration';

    return JsonEncoder.withIndent('  ').convert(h);
  }

  /// Pretty-prints the (unsigned) header for the Export preview pane.
  static String preview(SystemUser u) => buildJson(u);
}

/// Field-level validation mirroring snapd's `system-user` checks so the
/// user is told about problems *before* signing.
class AssertionValidation {
  static final _usernameRe = RegExp(r'^[a-z0-9][-a-z0-9._]*$');
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _serialRe =
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$');

  static List<String> userErrors(SystemUser u) {
    final e = <String>[];
    if (u.username.trim().isEmpty) {
      e.add('Username is required.');
    } else if (!_usernameRe.hasMatch(u.username.trim())) {
      e.add(
          'Username must start with a lowercase letter or digit and contain only lowercase letters, digits, ".", "_" and "-".');
    }
    if (u.email.trim().isEmpty) {
      e.add('E-mail address is required (it is part of the assertion index).');
    } else if (!_emailRe.hasMatch(u.email.trim())) {
      e.add('E-mail address looks invalid.');
    }
    if (u.forcePasswordChange && !u.hasPassword) {
      e.add('"Change password on first login" requires a password to be set.');
    }
    if (!u.hasAnyAuth) {
      e.add('Add at least one SSH key or a password so the user can log in.');
    }
    for (final k in u.sshKeys) {
      if (k.trim().isEmpty) {
        e.add('SSH key list contains an empty entry.');
        break;
      }
    }
    return e;
  }

  static List<String> deviceErrors(SystemUser u) {
    final e = <String>[];
    if (u.brandId.trim().isEmpty) {
      e.add('Brand ID is required (your Snap Store account ID).');
    }
    if (u.authorityId.trim().isEmpty) {
      e.add('Authority ID is required (defaults to the brand ID).');
    }
    if (u.hasSerials) {
      if (u.models.length != 1) {
        e.add('Serials require exactly one model to be specified.');
      }
      for (final s in u.serials) {
        if (s.trim().isEmpty || !_serialRe.hasMatch(s.trim())) {
          e.add('Serial "$s" looks invalid.');
          break;
        }
      }
    }
    for (final m in u.models) {
      if (m.trim().isEmpty) {
        e.add('Model list contains an empty entry.');
        break;
      }
    }
    return e;
  }

  static List<String> timingErrors(SystemUser u) {
    final e = <String>[];
    if (u.since == null) {
      e.add('"Valid from" is required.');
    }
    if (u.until == null) {
      e.add('"Valid until" is required.');
    }
    if (u.since != null && u.until != null) {
      if (!u.until!.isAfter(u.since!)) {
        e.add('"Valid until" must be after "Valid from".');
      } else if (!u.hasModels &&
          u.until!.difference(u.since!) > const Duration(days: 365)) {
        e.add(
            'Without a model, validity is limited to 365 days (snapd "global" '
            'assertion rule).');
      }
    }
    if (u.userUntilExpiration) {
      if (!u.hasPassword) {
        e.add('Removing the user at expiration requires a password.');
      }
      if (u.until == null) {
        e.add('Removing the user at expiration requires "Valid until".');
      }
    }
    return e;
  }

}
