import 'package:flutter_test/flutter_test.dart';
import 'package:user_assertion_editor/services/password_hasher.dart';

/// Reference vectors generated with glibc crypt (mkpasswd -m sha512crypt)
/// inside this container; passlib's pure-python implementation produced
/// identical output, so they are ground truth for the pure-Dart port.

final _vectors = [
  {'pw': "password", 'salt': "abc", 'rounds': 5000, 'hash': r'$6$abc$rvqzMBuMVukmply9mZJpW0wJMdDfgUKLDrSNxf9l66h/ytQiKNAdqHSj5YPJpxWJpVjRXibQXRddCl9xYHQnd0'},
  {'pw': "test1234", 'salt': "abcdefgh", 'rounds': 5000, 'hash': r'$6$abcdefgh$guPgFfxYz.aYapUzzQFw4l3WAXBjiGqOOQvKQJ0/fq6zvfLAh3U1G8fl2db.2VW5RT3JRsPIR9ahqo5DmHhgg0'},
  {'pw': "p@ssw0rd!x", 'salt': "./AbCdEf", 'rounds': 5000, 'hash': r'$6$./AbCdEf$EG2lX28mg5YnRbABo6GhvrJekfrRCZMHsaGpP1fWjpjGyVnZaKZs3ju.Z7XaiaOTJ79FCPzQJNE5Zkgx4C66f1'},
  {'pw': "hello world", 'salt': "Zz9yX8w7V6u5", 'rounds': 10000, 'hash': r'$6$rounds=10000$Zz9yX8w7V6u5$3u/AoFMnbsheFTh.9er8sKKCcfqBnsdBJf2frGaI7A4TFNlc6PfNACtALA0FszQFReIcO1I3rSif2bnt0QRP7.'},
  {'pw': "Ünïcodé-ßtr", 'salt': "s4lt", 'rounds': 5000, 'hash': r'$6$s4lt$dQMZcUVRh5HpIEBzv4GoldklrBV2vb9WaegJ2UyvvaifQ0d3bnomhjvZG/QIvvx7T/Rv3Sdyq7R1j74lSLdvr.'},
  {'pw': "", 'salt': "emptysalt", 'rounds': 5000, 'hash': r'$6$emptysalt$TrI.h19YNad.S.Xw2WEgON9ojBrkXYcCfZrEcOEa9k/Bp5Sw4dxhsyY0KdBJ5Vt2UbEFOMolXqrfnZHc1QRM..'},
  {'pw': "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", 'salt': "l", 'rounds': 5000, 'hash': r'$6$l$DPZtDS0BhgsBQx8Hft7c4gRweDMQVabrlUZiJhYSx16lYC9C.HGVEI.USCErT11ya.yqxiLOids/H3L1.fECe0'},
  {'pw': "secret", 'salt': "./Zz", 'rounds': 5000, 'hash': r'$6$./Zz$swhC2hTE7dhV5xy8wdH8TaY3ltp6Wx8.Yjt0GmT99Fygt8sd5Ql12W3mVfwyLrG/B3P2buJSSKFrv0LDLI9zK0'},
];

void main() {
  group('sha512Crypt (byte-for-byte vs glibc)', () {
    for (final v in _vectors) {
      test('salt=${v['salt']} rounds=${v['rounds']}', () {
        final actual = PasswordHasher.sha512Crypt(v['pw'] as String,
            salt: v['salt'] as String,
            rounds: v['rounds'] as int);
        expect(actual, v['hash']);
      });
    }
  });

  group('validateHash', () {
    test('accepts sha512crypt forms', () {
      expect(PasswordHasher.validateHash(r'$6$salt$abcdefgh'), null);
      expect(PasswordHasher.validateHash(r'$6$rounds=10000$salt$abcdefgh'), null);
      expect(PasswordHasher.validateHash(null), null);
      expect(PasswordHasher.validateHash(''), null);
    });
    test('rejects weak/malformed', () {
      expect(PasswordHasher.validateHash(r'$1$salt$md5'), isNotNull);
      expect(PasswordHasher.validateHash('not-a-hash'), isNotNull);
      expect(PasswordHasher.validateHash(r'$6$rounds=10$salt$abcdefgh'), isNotNull);
      expect(PasswordHasher.validateHash(r'$6$salt$bad!char'), isNotNull);
    });
  });

  test('random salt differs but verifies format', () {
    final a = PasswordHasher.sha512Crypt('x');
    final b = PasswordHasher.sha512Crypt('x');
    expect(a, isNot(b));
    expect(PasswordHasher.validateHash(a), null);
    expect(a, startsWith(r'$6$'));
  });
}
