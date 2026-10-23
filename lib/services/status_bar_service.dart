import 'dart:async';

import 'package:flutter/foundation.dart';

/// Severity of a [StatusMessage].
enum StatusSeverity { info, success, error }

/// One user-facing notification shown in the app's status bar.
class StatusMessage {
  final String text;
  final StatusSeverity severity;

  /// Bumped on every posted message so the fade animation re-triggers even
  /// when the same text is reported twice in a row.
  final int token;

  const StatusMessage({
    required this.text,
    required this.severity,
    required this.token,
  });
}

/// App-wide replacement for [SnackBar]: floating toasts are out of place on a
/// desktop surface (they cover content and vanish on a timer), so the most
/// recent message lives in the footer bar instead.
///
/// * **info / success** — auto-clear after [autoClearDuration];
/// * **error** — stays until dismissed (close button, Escape, or a newer
///   message).
class StatusBarService extends ChangeNotifier {
  StatusBarService._();

  static final StatusBarService instance = StatusBarService._();

  static const Duration autoClearDuration = Duration(seconds: 5);

  StatusMessage? _current;
  int _token = 0;
  Timer? _autoClear;

  StatusMessage? get current => _current;
  bool get hasCurrent => _current != null;

  void show(String text, {StatusSeverity severity = StatusSeverity.info}) {
    _cancelAutoClear();
    _current = StatusMessage(
        text: text, severity: severity, token: ++_token);
    notifyListeners();
    if (severity != StatusSeverity.error) {
      _autoClear = Timer(autoClearDuration, clear);
    }
  }

  void error(String text) => show(text, severity: StatusSeverity.error);
  void success(String text) => show(text, severity: StatusSeverity.success);

  void clear() {
    _cancelAutoClear();
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  void _cancelAutoClear() {
    _autoClear?.cancel();
    _autoClear = null;
  }
}
