import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

/// Password hashing for offline sign-in. PBKDF2-HMAC-SHA256 with a per-account
/// random salt, run on a background isolate so the login screen stays smooth.
class OfflineCredentials {
  OfflineCredentials._();

  static const iterations = 100000;

  static String newSalt() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  static Future<String> hash(String password, String salt, int iterations) =>
      compute(_pbkdf2, (password, salt, iterations));

  static String _pbkdf2((String, String, int) args) {
    final (password, salt, rounds) = args;
    final hmac = Hmac(sha256, utf8.encode(password));
    var block = hmac.convert([...base64Decode(salt), 0, 0, 0, 1]).bytes;
    final result = Uint8List.fromList(block);
    for (var i = 1; i < rounds; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    return base64Encode(result);
  }

  /// Comparison that takes the same time wherever the strings first differ.
  static bool matches(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
