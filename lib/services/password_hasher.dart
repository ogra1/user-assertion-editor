import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

/// Generates crypt(3)-compatible `$6$...` (sha512crypt) password hashes in
/// pure Dart, plus validation of pre-computed hashes.
///
/// snapd requires the `password` header to be of the form
/// `$integer-id$salt$hash` (optionally `$integer-id$rounds=N$salt$hash`)
/// with id >= 6, so this implements the SHA-512-Crypt algorithm
/// (as specified in the glibc / Openwall sha2crypt spec).
class PasswordHasher {
  static const int _defaultRounds = 5000;
  /// crypt(3) hash64 alphabet — digits immediately after './', then
  /// uppercase, then lowercase. (Matters: NOT standard base64 order.)
  static const String _cryptChars =
      './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  /// (even, odd) permutation indices into [perms] for rounds 0..41.
  static const List<(int, int)> _cDigestOffsets = [
    (0, 3), (5, 1), (5, 3), (1, 2), (5, 1), (5, 3),
    (1, 3), (4, 1), (5, 3), (1, 3), (5, 0), (5, 3),
    (1, 3), (5, 1), (4, 3), (1, 3), (5, 1), (5, 2),
    (1, 3), (5, 1), (5, 3),
  ];

  /// Byte order for the final sha512 digest before 6-bit encoding.
  static const List<int> _transposeMap = [
    42, 21, 0, 1, 43, 22, 23, 2, 44, 45, 24, 3,
    4, 46, 25, 26, 5, 47, 48, 27, 6, 7, 49, 28,
    29, 8, 50, 51, 30, 9, 10, 52, 31, 32, 11, 53,
    54, 33, 12, 13, 55, 34, 35, 14, 56, 57, 36, 15,
    16, 58, 37, 38, 17, 59, 60, 39, 18, 19, 61, 40,
    41, 20, 62, 63,
  ];

  static final Random _random = Random.secure();

  /// Random 16-char crypt(3) salt (allowed salt chars only).
  static String randomSalt() {
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      sb.write(_cryptChars[_random.nextInt(_cryptChars.length)]);
    }
    return sb.toString();
  }

  /// Hashes [password]; result looks like `$6$<salt>$<b64>` (5000 rounds,
  /// rounds omitted) or `$6$rounds=N$<salt>$<b64>` otherwise.
  static String sha512Crypt(String password,
      {String? salt, int rounds = _defaultRounds}) {
    final s = (salt ?? randomSalt()).substring(0, min(16, salt?.length ?? 16));
    final b64 = _rawSha512Crypt(utf8.encode(password), utf8.encode(s), rounds);
    if (rounds == _defaultRounds) {
      return r'$6$' + s + r'$' + b64;
    }
    return r'$6$rounds=' + rounds.toString() + r'$' + s + r'$' + b64;
  }

  /// hash64 (crypt base-64) LITTLE-endian encoder, ported from passlib's
  /// LazyBase64Engine._encode_bytes_little. 3 input bytes -> 4 chars:
  /// c0=v1&0x3f, c1=((v2&0x0f)<<2)|(v1>>6), c2=((v3&0x03)<<4)|(v2>>4), c3=v3>>2.
  /// A 64-byte (sha512) source yields 85 chars + 1 tail char = 86.
  static String _b64Enc(List<int> input) {
    final sb = StringBuffer();
    final n = input.length;
    var i = 0;
    for (; i + 3 <= n; i += 3) {
      final v1 = input[i];
      final v2 = input[i + 1];
      final v3 = input[i + 2];
      sb.write(_cryptChars[v1 & 0x3f]);
      sb.write(_cryptChars[((v2 & 0x0f) << 2) | (v1 >> 6)]);
      sb.write(_cryptChars[((v3 & 0x03) << 4) | (v2 >> 4)]);
      sb.write(_cryptChars[v3 >> 2]);
    }
    final tail = n - i;
    if (tail == 1) {
      final v1 = input[i];
      sb.write(_cryptChars[v1 & 0x3f]);
      sb.write(_cryptChars[v1 >> 6]);
    } else if (tail == 2) {
      final v1 = input[i];
      final v2 = input[i + 1];
      sb.write(_cryptChars[v1 & 0x3f]);
      sb.write(_cryptChars[((v2 & 0x0f) << 2) | (v1 >> 6)]);
      sb.write(_cryptChars[v2 >> 4]);
    }
    return sb.toString();
  }

  /// The SHA-512-Crypt core (Openwall spec), matching glibc's crypt_r.
  static String _rawSha512Crypt(List<int> pwd, List<int> salt, int rounds) {
    List<int> h512(List<int> data) => crypto.sha512.convert(data).bytes;
    final saltLen = salt.length;


    // db = SHA512(P + S + P)
    final db = h512([...pwd, ...salt, ...pwd]);

    // da = SHA512(P + S + (db repeated len(P) times) +
    //              (db if bit of len(P) set else P) for each bit, MSB last)
    final aCtx = _StreamingSha512();
    aCtx.update(pwd);
    aCtx.update(salt);
    final repeated = _repeat(db, pwd.length);
    aCtx.update(repeated);
    var i = pwd.length;
    while (i > 0) {
      aCtx.update((i & 1) == 1 ? db : pwd);
      i >>= 1;
    }
    final da = aCtx.digest();

    // dp = repeat(SHA512(P * len(P)), len(P))  [passlib: pwd * pwd_len]
    final dpDigest = h512(_times(pwd, pwd.length));
    final dp = _repeat(dpDigest, pwd.length);

    // ds = SHA512(S * (16 + da[0])) truncated to len(S)  [passlib: salt * (16+da[0])]
    final dsDigest = h512(_times(salt, 16 + da[0]));
    final ds = dsDigest.sublist(0, saltLen);

    // dc rounds
    final perms = [dp, [...dp, ...dp], [...dp, ...ds],
        [...dp, ...ds, ...dp], [...ds, ...dp], [...ds, ...dp, ...dp]];

    var dc = da;
    var blocks = rounds ~/ 42;
    var tail = rounds % 42;
    while (blocks > 0) {
      for (final (even, odd) in _cDigestOffsets) {
        dc = h512([...perms[odd], ...h512([...dc, ...perms[even]])]);
      }
      blocks--;
    }
    if (tail > 0) {
      final pairs = tail >> 1;
      for (var k = 0; k < pairs; k++) {
        final (even, odd) = _cDigestOffsets[k];
        dc = h512([...perms[odd], ...h512([...dc, ...perms[even]])]);
      }
      if ((tail & 1) == 1) {
        dc = h512([...dc, ...perms[_cDigestOffsets[pairs].$1]]);
      }
    }

    // encode
    final out = <int>[];
    for (final idx in _transposeMap) {
      out.add(dc[idx]);
    }
    return _b64Enc(out);
  }

  /// Concatenates [src] [n] times (no truncation) — matches passlib's
  /// `pwd * pwd_len` / `salt * (16 + da[0])` semantics.
  static List<int> _times(List<int> src, int n) {
    final out = List<int>.filled(src.length * n, 0);
    for (var r = 0; r < n; r++) {
      out.setRange(r * src.length, (r + 1) * src.length, src);
    }
    return out;
  }

  /// Repeats [src] to exactly [size] bytes (truncating) — passlib's
  /// `repeat_string(digest, pwd_len)`.
  static List<int> _repeat(List<int> src, int size) {
    if (src.isEmpty) return List.filled(size, 0);
    final out = List<int>.filled(size, 0);
    for (var i = 0; i < size; i++) {
      out[i] = src[i % src.length];
    }
    return out;
  }

  /// Validates that [hash] has the form snapd accepts for `password`:
  /// `$id$salt$hash` (optionally `$id$rounds=N$salt$hash`), id >= 6.
  /// Returns an error message, or null when acceptable (null/empty = no
  /// password, which is valid).
  static String? validateHash(String? hash) {
    if (hash == null || hash.isEmpty) return null;
    final parts = hash.split(r'$');
    if (parts.length != 4 && parts.length != 5) {
      return 'Hash must have the form: dollar-6, salt, hash (crypt form).';
    }
    final idStr = parts[1];
    if (!RegExp(r'^\d+$').hasMatch(idStr)) {
      return 'Hash id must be an integer.';
    }
    if (int.parse(idStr) < 6) {
      return 'Only ids >= 6 (sha512crypt) are accepted by snapd.';
    }
    if (parts.length == 5) {
      final rp = parts[2];
      if (!rp.startsWith('rounds=')) {
        return 'Field 2 must be "rounds=N".';
      }
      final n = int.tryParse(rp.substring(7));
      if (n == null || n < 5000 || n > 999999999) {
        return 'Rounds must be between 5000 and 999999999.';
      }
    }
    final valid = RegExp(r'^[a-zA-Z0-9./]+$');
    for (var k = 2; k < parts.length; k++) {
      final field = parts[k];
      // The optional "rounds=N" field is digits, not crypt chars.
      if (parts.length == 5 && k == 2) {
        continue;
      }
      if (field.isEmpty) return 'Hash has an empty field.';
      if (!valid.hasMatch(field)) {
        return 'Hash field ${k - 1} contains invalid characters.';
      }
    }
    return null;
  }
}

/// Minimal streaming SHA-512 wrapper over package:crypto.
class _StreamingSha512 {
  final List<int> _buffer = [];

  void update(List<int> data) => _buffer.addAll(data);

  List<int> digest() => crypto.sha512.convert(_buffer).bytes;
}
