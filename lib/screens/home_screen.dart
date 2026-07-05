import 'package:flutter/material.dart';

import '../models/commitment_log_entry.dart';
import '../models/draw_result.dart';
import '../models/ticket_range.dart';
import '../services/app_integrity_service.dart';
import '../services/storage_service.dart';
import 'draw_screen.dart';
import 'ranges_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = StorageService();
  final _integrity = AppIntegrityService();
  bool _loading = true;
  List<TicketRange> _ranges = [];
  List<DrawResult> _history = [];
  List<CommitmentLogEntry> _commitmentLog = [];
  String? _exeFingerprint;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _integrity.computeExecutableFingerprint().then((fingerprint) {
      if (!mounted) return;
      setState(() => _exeFingerprint = fingerprint);
    });
  }

  Future<void> _load() async {
    final ranges = await _storage.loadRanges();
    final history = await _storage.loadHistory();
    final commitmentLog = await _storage.loadCommitmentLog();
    setState(() {
      _ranges = ranges;
      _history = history;
      _commitmentLog = commitmentLog;
      _loading = false;
    });
  }

  void _onRangesChanged(List<TicketRange> ranges) {
    setState(() => _ranges = ranges);
    _storage.saveRanges(ranges);
  }

  void _onHistoryChanged(List<DrawResult> history) {
    setState(() => _history = history);
    _storage.saveHistory(history);
  }

  void _onCommitmentLogChanged(List<CommitmentLogEntry> log) {
    setState(() => _commitmentLog = log);
    _storage.saveCommitmentLog(log);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = [
      DrawScreen(
        key: ValueKey('draw-${_ranges.length}'),
        ranges: _ranges,
        history: _history,
        onHistoryChanged: _onHistoryChanged,
        commitmentLog: _commitmentLog,
        onCommitmentLogChanged: _onCommitmentLogChanged,
        exeFingerprint: _exeFingerprint,
      ),
      RangesScreen(
        ranges: _ranges,
        onChanged: _onRangesChanged,
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Κλήρωση',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Λαχεία',
          ),
        ],
      ),
    );
  }
}
