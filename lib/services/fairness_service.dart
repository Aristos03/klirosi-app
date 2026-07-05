import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Implements a "provably fair" draw scheme, the same idea used by
/// transparent online casinos:
///
/// 1. Before drawing, a secret random seed is generated and its SHA-256
///    hash (the "commitment") is shown/announced publicly.
/// 2. The exact microsecond the organizer presses "start" is captured
///    automatically, so the outcome can't have been precomputed -- nobody,
///    not even the organizer, controls that value precisely. An optional
///    audience-supplied number can be added on top for extra assurance.
/// 3. The winner is derived deterministically from
///    sha256("seed:audienceNumber:pressMoment:nonce") mod poolSize, so
///    anyone can redo the same arithmetic afterwards and confirm the result.
/// 4. After the draw, the seed is revealed; hashing it must match the
///    commitment shown beforehand, proving it wasn't swapped.
class FairnessService {
  final _secureRandom = Random.secure();

  String generateSeed() {
    final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();

  /// Returns the index (into a pool sorted ascending) selected by the
  /// committed seed, the optional audience number, the automatic
  /// press-moment token, and the draw's nonce.
  int computeWinnerIndex({
    required String seed,
    required String audienceNumber,
    required String pressMoment,
    required int nonce,
    required int poolSize,
  }) {
    final hashHex = sha256Hex('$seed:$audienceNumber:$pressMoment:$nonce');
    final bigInt = BigInt.parse(hashHex, radix: 16);
    return (bigInt % BigInt.from(poolSize)).toInt();
  }
}
