import 'dart:io';

import 'package:crypto/crypto.dart';

/// Computes a SHA-256 fingerprint of the currently running executable, so
/// it can be shown on screen (and published beforehand). Anyone can then
/// verify that the exact same binary was used at the event -- no need to
/// trust a claim that "a different program" produced the results.
class AppIntegrityService {
  Future<String?> computeExecutableFingerprint() async {
    try {
      final exeFile = File(Platform.resolvedExecutable);
      final bytes = await exeFile.readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (_) {
      return null;
    }
  }
}
