/// A system-user assertion to be created and signed.
///
/// Mirrors the `system-user` assertion type from the snapd docs
/// (https://documentation.ubuntu.com/ubuntu-core/en/latest/reference/assertions/system-user.html):
/// brand-signed assertions that let unmanaged Ubuntu Core devices create a
/// local system user without console-conf.
class SystemUser {
  // --- Identity -----------------------------------------------------------
  String name = '';
  String email = '';
  String username = '';

  // --- Authentication -----------------------------------------------------
  /// crypt(3)-compatible hashed password (`$6$...`), or null for
  /// SSH-key-only login.
  String? passwordHash;
  bool forcePasswordChange = false;

  /// Public SSH keys, one per entry, e.g.
  /// `ssh-ed25519 AAAAC3Nza... user@host`.
  final List<String> sshKeys = [];

  // --- Scope --------------------------------------------------------------
  /// Store account ID of the brand (defaults to [authorityId]).
  String brandId = '';
  String authorityId = '';
  /// The snapd series; "16" is the default series that has been in use
  /// since snapd's inception and is still the only current one.
  String series = '16';

  /// Models the assertion applies to. Empty = "global" (any model of the
  /// brand), which snapd limits to 365-day validity.
  final List<String> models = [];

  /// Device serials; when non-empty, [models] must contain exactly one
  /// model (snapd requirement).
  final List<String> serials = [];

  // --- Validity window ------------------------------------------------------
  /// Whether the user is created on first boot (true) or only when the
  /// assertion is imported (false).
  bool createOnFirstBoot = true;

  DateTime? since;
  DateTime? until;

  /// `user-presence: until-expiration` — the user is removed when the
  /// assertion expires. Requires format 2 (always emitted) and a password.
  bool userUntilExpiration = false;

  // --- Signing result -------------------------------------------------------
  /// The complete signed chain (system-user + account-key + account), as
  /// `snap sign --chain` emitted it.
  String? signedChain;

  /// The plain JSON header that was signed (kept for the preview pane).
  String? jsonHeader;

  SystemUser();

  /// A fully-populated SSO-style default: SSH-key login, no password,
  /// valid for 30 days from now — the simplest valid assertion.
  factory SystemUser.defaults() {
    final now = DateTime.now().toUtc();
    return SystemUser()
      ..since = now
      ..until = now.add(const Duration(days: 30));
  }

  bool get hasModels => models.isNotEmpty;
  bool get hasSerials => serials.isNotEmpty;

  bool get hasPassword =>
      passwordHash != null && passwordHash!.isNotEmpty;
  bool get hasSshKeys =>
      sshKeys.any((k) => k.trim().isNotEmpty);

  bool get hasAnyAuth => hasPassword || hasSshKeys;

  /// Copy of the UTC [d] formatted as RFC 3339 (e.g. 2026-05-16T18:06:04Z).
  static String rfc3339(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-'
        '${two(u.month)}-${two(u.day)}'
        'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }
}
