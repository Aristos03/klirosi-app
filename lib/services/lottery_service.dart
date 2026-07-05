import 'dart:math';

import '../models/ticket_range.dart';

class LotteryService {
  final _random = Random();

  List<int> availableNumbers(
    List<TicketRange> ranges, {
    Set<int> exclude = const {},
  }) {
    final numbers = <int>{};
    for (final range in ranges) {
      for (var n = range.start; n <= range.end; n++) {
        if (!exclude.contains(n)) numbers.add(n);
      }
    }
    return numbers.toList();
  }

  int? pickWinner(
    List<TicketRange> ranges, {
    Set<int> exclude = const {},
  }) {
    final pool = availableNumbers(ranges, exclude: exclude);
    if (pool.isEmpty) return null;
    return pool[_random.nextInt(pool.length)];
  }

  bool numbersOverlap(TicketRange candidate, List<TicketRange> existing) {
    for (final r in existing) {
      if (candidate.start <= r.end && candidate.end >= r.start) return true;
    }
    return false;
  }
}
