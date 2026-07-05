import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/commitment_log_entry.dart';
import '../models/draw_result.dart';
import '../models/ticket_range.dart';

class StorageService {
  static const _rangesKey = 'ticket_ranges';
  static const _historyKey = 'draw_history';
  static const _commitmentLogKey = 'commitment_log';

  Future<List<TicketRange>> loadRanges() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rangesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => TicketRange.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveRanges(List<TicketRange> ranges) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(ranges.map((r) => r.toJson()).toList());
    await prefs.setString(_rangesKey, raw);
  }

  Future<List<DrawResult>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => DrawResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveHistory(List<DrawResult> history) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(history.map((h) => h.toJson()).toList());
    await prefs.setString(_historyKey, raw);
  }

  /// The commitment log is intentionally separate from [loadHistory] /
  /// [saveHistory] and is never touched by "clear history" -- it's a
  /// permanent record of every commitment hash ever shown, so nobody can
  /// quietly discard an unfavourable attempt.
  Future<List<CommitmentLogEntry>> loadCommitmentLog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_commitmentLogKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => CommitmentLogEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCommitmentLog(List<CommitmentLogEntry> log) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(log.map((e) => e.toJson()).toList());
    await prefs.setString(_commitmentLogKey, raw);
  }
}
