import 'dart:io';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';

import '../models/commitment_log_entry.dart';
import '../models/draw_result.dart';
import '../models/ticket_range.dart';
import '../services/fairness_service.dart';
import '../services/lottery_service.dart';

class DrawScreen extends StatefulWidget {
  const DrawScreen({
    super.key,
    required this.ranges,
    required this.history,
    required this.onHistoryChanged,
    required this.commitmentLog,
    required this.onCommitmentLogChanged,
    this.exeFingerprint,
  });

  final List<TicketRange> ranges;
  final List<DrawResult> history;
  final ValueChanged<List<DrawResult>> onHistoryChanged;
  final List<CommitmentLogEntry> commitmentLog;
  final ValueChanged<List<CommitmentLogEntry>> onCommitmentLogChanged;
  final String? exeFingerprint;

  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends State<DrawScreen> with TickerProviderStateMixin {
  static const _maxDigits = 6;
  static const _cellWidth = 76.0;
  static const _cellHeight = 66.0;
  static const _reelGap = 10.0;
  // Slow, deliberately agonizing pacing: each digit (left to right) locks in
  // noticeably later than the one before it.
  static const _baseDurationMs = 3200;
  static const _staggerMs = 1000;

  final _lottery = LotteryService();
  final _fairness = FairnessService();
  final _audienceController = TextEditingController();

  late final ConfettiController _confettiController = ConfettiController(
    duration: const Duration(seconds: 3),
  );

  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _revealScale = CurvedAnimation(
    parent: _revealController,
    curve: Curves.elasticOut,
  );

  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final AnimationController _bounceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..repeat(reverse: true);

  // One controller per digit column (index 0 = leftmost/most significant).
  // Each column's duration is set individually in _startDraw so later
  // columns lock in noticeably after earlier ones.
  late final List<AnimationController> _digitControllers = List.generate(
    _maxDigits,
    (i) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _baseDurationMs),
    ),
  );
  final List<Animation<double>?> _digitAnimations = List.filled(
    _maxDigits,
    null,
  );

  late final List<DrawResult> _history = List.of(widget.history);
  late final List<CommitmentLogEntry> _commitmentLog = List.of(
    widget.commitmentLog,
  );
  bool _excludePreviousWinners = true;
  bool _isDrawing = false;
  bool _showReveal = false;
  int? _winnerNumber;

  List<int> get _pool => _lottery.availableNumbers(
    widget.ranges,
    exclude: _excludePreviousWinners
        ? _history.map((h) => h.number).toSet()
        : const {},
  );

  int get _digitCount {
    if (widget.ranges.isEmpty) return 3;
    final maxEnd = widget.ranges.map((r) => r.end).reduce(max);
    return maxEnd.toString().length.clamp(3, _maxDigits);
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _revealController.dispose();
    _glowController.dispose();
    _bounceController.dispose();
    for (final c in _digitControllers) {
      c.dispose();
    }
    _audienceController.dispose();
    super.dispose();
  }

  void _logCommitment(CommitmentLogEntry entry) {
    setState(() => _commitmentLog.add(entry));
    widget.onCommitmentLogChanged(_commitmentLog);
  }

  void _updateLastCommitment({required String status, int? drawNumber}) {
    if (_commitmentLog.isEmpty) return;
    setState(() {
      _commitmentLog[_commitmentLog.length - 1] = _commitmentLog.last
          .copyWith(status: status, drawNumber: drawNumber);
    });
    widget.onCommitmentLogChanged(_commitmentLog);
  }

  Future<void> _beginDrawFlow() async {
    if (_pool.isEmpty || _isDrawing) return;

    final seed = _fairness.generateSeed();
    final commitmentHash = _fairness.sha256Hex(seed);
    _audienceController.clear();

    // Recorded the instant the hash is shown -- this entry can never be
    // silently erased, even if the organizer cancels and never proceeds.
    _logCommitment(
      CommitmentLogEntry(
        timestamp: DateTime.now(),
        commitmentHash: commitmentHash,
        status: 'shown',
      ),
    );

    final confirmed = await _showCommitDialog(commitmentHash);
    if (confirmed != true) {
      _updateLastCommitment(status: 'cancelled');
      return;
    }

    // Captured at the exact moment the organizer confirms, down to the
    // microsecond -- this can't be predicted or precomputed in advance,
    // which is what keeps the draw fair even without audience input.
    final pressMoment = DateTime.now().toIso8601String();
    final audienceNumber = _audienceController.text.trim();
    final winner = await _startDraw(
      seed: seed,
      audienceNumber: audienceNumber,
      pressMoment: pressMoment,
    );
    _updateLastCommitment(status: 'used', drawNumber: winner);
  }

  Future<bool?> _showCommitDialog(String commitmentHash) {
    const revealDelay = Duration(seconds: 5);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FutureBuilder<void>(
        future: Future.delayed(revealDelay),
        builder: (context, snapshot) {
          final waitingDone = snapshot.connectionState == ConnectionState.done;
          return AlertDialog(
            title: const Text('Προετοιμασία Κλήρωσης'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Η εφαρμογή δημιούργησε έναν μυστικό κωδικό για αυτή '
                    'την κλήρωση. Δείξτε στο κοινό το παρακάτω αποτύπωμα '
                    '(hash) — όσοι θέλουν μπορούν να το φωτογραφίσουν '
                    'ΤΩΡΑ. Αποδεικνύει ότι το αποτέλεσμα δεν μπορεί να '
                    'αλλάξει μετά.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            commitmentHash,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Αντιγραφή',
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: commitmentHash),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.exeFingerprint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Αποτύπωμα εφαρμογής (SHA-256): ${widget.exeFingerprint}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Προαιρετικό: αν έχετε κάποιον (π.χ. συμβολαιογράφο) '
                    'να πει έναν αριθμό για επιπλέον διαφάνεια, γράψτε '
                    'τον εδώ. Δεν είναι απαραίτητο — η ακριβής στιγμή που '
                    'θα πατήσετε "Ξεκίνα" προστίθεται ούτως ή άλλως '
                    'αυτόματα στον υπολογισμό.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _audienceController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Αριθμός από το κοινό (προαιρετικό)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Άκυρο'),
              ),
              FilledButton(
                onPressed: waitingDone
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(
                  waitingDone ? 'Ξεκίνα την Κλήρωση' : 'Δείξτε το αποτύπωμα...',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<int?> _startDraw({
    required String seed,
    required String audienceNumber,
    required String pressMoment,
  }) async {
    final excluded = _excludePreviousWinners
        ? _history.map((h) => h.number).toSet()
        : <int>{};
    final sortedPool = _lottery.availableNumbers(
      widget.ranges,
      exclude: excluded,
    )..sort();
    if (sortedPool.isEmpty || _isDrawing) return null;

    final nonce = _history.length;
    final commitmentHash = _fairness.sha256Hex(seed);
    final index = _fairness.computeWinnerIndex(
      seed: seed,
      audienceNumber: audienceNumber,
      pressMoment: pressMoment,
      nonce: nonce,
      poolSize: sortedPool.length,
    );
    final winner = sortedPool[index];

    final digitCount = _digitCount;
    final winnerDigits = winner
        .toString()
        .padLeft(digitCount, '0')
        .split('')
        .map(int.parse)
        .toList();

    _glowController.stop();
    setState(() {
      _isDrawing = true;
      _showReveal = false;
      _winnerNumber = null;
      for (var pos = 0; pos < _maxDigits; pos++) {
        if (pos >= digitCount) {
          _digitAnimations[pos] = null;
          continue;
        }
        final controller = _digitControllers[pos]
          ..duration = Duration(
            milliseconds: _baseDurationMs + pos * _staggerMs,
          )
          ..reset();
        final targetDigit = winnerDigits[pos];
        final end = 30 + targetDigit;
        _digitAnimations[pos] = Tween<double>(begin: 0, end: end.toDouble())
            .animate(
              CurvedAnimation(parent: controller, curve: Curves.easeOutExpo),
            );
      }
    });

    final futures = [
      for (var pos = 0; pos < digitCount; pos++)
        _digitControllers[pos].forward(),
    ];
    await Future.wait(futures);
    if (!mounted) return winner;

    setState(() {
      _winnerNumber = winner;
      _isDrawing = false;
      _showReveal = true;
      _history.insert(
        0,
        DrawResult(
          number: winner,
          timestamp: DateTime.now(),
          seed: seed,
          commitmentHash: commitmentHash,
          audienceNumber: audienceNumber,
          pressMoment: pressMoment,
          nonce: nonce,
          poolSize: sortedPool.length,
          rangesSnapshot: widget.ranges
              .map(
                (r) => r.label.isEmpty
                    ? '${r.start}-${r.end}'
                    : '${r.label}: ${r.start}-${r.end}',
              )
              .toList(),
          excludedNumbers: excluded.toList()..sort(),
        ),
      );
    });
    widget.onHistoryChanged(_history);
    _confettiController.play();
    _revealController
      ..reset()
      ..forward();
    _glowController
      ..reset()
      ..repeat(reverse: true);
    return winner;
  }

  String _buildProofText(DrawResult entry) {
    final buffer = StringBuffer()
      ..writeln('ΑΠΟΔΕΙΞΗ ΔΙΑΦΑΝΕΙΑΣ ΚΛΗΡΩΣΗΣ')
      ..writeln('=' * 40)
      ..writeln()
      ..writeln(
        'Ημερομηνία: '
        '${DateFormat('dd/MM/yyyy HH:mm:ss').format(entry.timestamp)}',
      )
      ..writeln('Νικητήριος αριθμός: ${entry.number}');
    if (widget.exeFingerprint != null) {
      buffer.writeln('Αποτύπωμα εφαρμογής (SHA-256): ${widget.exeFingerprint}');
    }
    buffer
      ..writeln()
      ..writeln('Ομάδες λαχείων:');
    if (entry.rangesSnapshot.isEmpty) {
      buffer.writeln('  (δεν καταγράφηκαν)');
    } else {
      for (final r in entry.rangesSnapshot) {
        buffer.writeln('  - $r');
      }
    }
    buffer
      ..writeln()
      ..writeln(
        'Εξαιρέθηκαν (προηγούμενοι νικητές): '
        '${entry.excludedNumbers.isEmpty ? "κανένας" : entry.excludedNumbers.join(", ")}',
      )
      ..writeln('Σύνολο διαθέσιμων λαχείων εκείνη τη στιγμή: ${entry.poolSize}')
      ..writeln()
      ..writeln('--- Στοιχεία Αποδεικτικά Δίκαιης Κλήρωσης ---')
      ..writeln('Δέσμευση (SHA-256, ανακοινώθηκε ΠΡΙΝ την κλήρωση):')
      ..writeln('  ${entry.commitmentHash}')
      ..writeln(
        'Αριθμός από το κοινό: '
        '${entry.audienceNumber.isEmpty ? "(δεν χρησιμοποιήθηκε)" : entry.audienceNumber}',
      )
      ..writeln('Ακριβής στιγμή πατήματος (αυτόματο, μη προβλέψιμο):')
      ..writeln('  ${entry.pressMoment}')
      ..writeln('Αριθμός κλήρωσης (nonce): ${entry.nonce}')
      ..writeln('Μυστικός σπόρος (αποκαλύφθηκε ΜΕΤΑ την κλήρωση):')
      ..writeln('  ${entry.seed}')
      ..writeln()
      ..writeln('Πώς να επαληθεύσετε:')
      ..writeln('1. Υπολογίστε SHA-256("${entry.seed}") και επιβεβαιώστε ότι')
      ..writeln('   ισούται με τη δέσμευση παραπάνω.')
      ..writeln(
        '2. Υπολογίστε SHA-256("${entry.seed}:${entry.audienceNumber}:'
        '${entry.pressMoment}:${entry.nonce}").',
      )
      ..writeln('3. Μετατρέψτε το αποτέλεσμα από δεκαεξαδικό σε δεκαδικό')
      ..writeln(
        '   ακέραιο και βρείτε το υπόλοιπο διαιρώντας με '
        '${entry.poolSize}.',
      )
      ..writeln('4. Ταξινομήστε τα διαθέσιμα λαχεία αύξουσα. Ο αριθμός στη')
      ..writeln('   θέση που προέκυψε (ξεκινώντας από το 0) πρέπει να είναι')
      ..writeln('   ο νικητήριος αριθμός.');
    return buffer.toString();
  }

  Future<void> _exportProof(DrawResult entry) async {
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$userProfile\\Documents\\Κληρώσεις Αποδεικτικά');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeTimestamp = DateFormat(
        'yyyy-MM-dd_HH-mm-ss',
      ).format(entry.timestamp);
      final file = File(
        '${dir.path}\\apodeixi_${entry.number}_$safeTimestamp.txt',
      );
      await file.writeAsString(_buildProofText(entry));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Αποθηκεύτηκε: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Αποτυχία εξαγωγής: $e')));
    }
  }

  void _showProofDetails(DrawResult entry) {
    if (!entry.hasProof) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Απόδειξη Διαφάνειας Κλήρωσης'),
          content: const Text(
            'Αυτή η κλήρωση έγινε πριν προστεθεί η λειτουργία διαφάνειας, '
            'οπότε δεν υπάρχουν καταγεγραμμένα στοιχεία απόδειξης για αυτήν.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Κλείσιμο'),
            ),
          ],
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Απόδειξη Διαφάνειας Κλήρωσης'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              _buildProofText(entry),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Κλείσιμο'),
          ),
          FilledButton.icon(
            onPressed: () => _exportProof(entry),
            icon: const Icon(Icons.download),
            label: const Text('Εξαγωγή .txt'),
          ),
        ],
      ),
    );
  }

  void _dismissReveal() {
    if (!_showReveal) return;
    setState(() => _showReveal = false);
    _glowController.stop();
  }

  String _buildCommitmentLogText() {
    final buffer = StringBuffer()
      ..writeln('ΜΟΝΙΜΟ ΙΣΤΟΡΙΚΟ ΔΕΣΜΕΥΣΕΩΝ (COMMITMENT LOG)')
      ..writeln('=' * 40)
      ..writeln(
        'Κάθε φορά που εμφανίστηκε αποτύπωμα (hash) στην οθόνη, ακόμα κι αν '
        'η κλήρωση ακυρώθηκε και δεν ολοκληρώθηκε ποτέ, καταγράφεται εδώ. '
        'Αυτή η λίστα δεν μπορεί να διαγραφεί από το κουμπί "Καθαρισμός".',
      )
      ..writeln();
    if (widget.exeFingerprint != null) {
      buffer
        ..writeln('Αποτύπωμα εκτελέσιμου (SHA-256): ${widget.exeFingerprint}')
        ..writeln();
    }
    if (_commitmentLog.isEmpty) {
      buffer.writeln('(δεν έχει εμφανιστεί καμία δέσμευση ακόμα)');
    }
    for (var i = 0; i < _commitmentLog.length; i++) {
      final e = _commitmentLog[i];
      buffer
        ..writeln(
          '${i + 1}. ${DateFormat('dd/MM/yyyy HH:mm:ss').format(e.timestamp)} '
          '— κατάσταση: ${e.status}'
          '${e.drawNumber != null ? ' — νικητής: ${e.drawNumber}' : ''}',
        )
        ..writeln('   ${e.commitmentHash}');
    }
    return buffer.toString();
  }

  void _showCommitmentLogDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ιστορικό Δεσμεύσεων'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: SelectableText(
              _buildCommitmentLogText(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Κλείσιμο'),
          ),
          FilledButton.icon(
            onPressed: _exportCommitmentLog,
            icon: const Icon(Icons.download),
            label: const Text('Εξαγωγή .txt'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCommitmentLog() async {
    try {
      final userProfile = Platform.environment['USERPROFILE'] ?? '.';
      final dir = Directory('$userProfile\\Documents\\Κληρώσεις Αποδεικτικά');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final safeTimestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final file = File('${dir.path}\\istoriko_desmeuseon_$safeTimestamp.txt');
      await file.writeAsString(_buildCommitmentLogText());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Αποθηκεύτηκε: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Αποτυχία εξαγωγής: $e')));
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Καθαρισμός ιστορικού'),
        content: const Text(
          'Θα διαγραφούν όλες οι προηγούμενες κληρώσεις. Συνέχεια;',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Καθαρισμός'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _glowController.stop();
    setState(() {
      _history.clear();
      _winnerNumber = null;
      _showReveal = false;
    });
    widget.onHistoryChanged(_history);
  }

  @override
  Widget build(BuildContext context) {
    final totalTickets = widget.ranges.fold<int>(0, (sum, r) => sum + r.count);
    final poolSize = _pool.length;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Κλήρωση'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Ιστορικό Δεσμεύσεων (μόνιμο, μη διαγράψιμο)',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: _showCommitmentLogDialog,
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primary.withValues(alpha: 0.35),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.5),
            radius: 1.3,
            colors: [
              Color.lerp(
                scheme.primary,
                Colors.black,
                0.55,
              )!.withValues(alpha: 0.35),
              const Color(0xFF0a0b0f),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            SafeArea(
              child: Column(
                children: [
                  _buildHeroHeader(scheme, totalTickets, poolSize),
                  const SizedBox(height: 6),
                  _buildSponsorStrip(scheme),
                  const SizedBox(height: 6),
                  _buildReel(scheme),
                  const SizedBox(height: 8),
                  _buildDrawButton(scheme, totalTickets, poolSize),
                  const SizedBox(height: 6),
                  _buildExcludeToggle(scheme),
                  const SizedBox(height: 4),
                  Expanded(child: _buildHistoryCard(scheme)),
                ],
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                numberOfParticles: 30,
                maxBlastForce: 20,
                minBlastForce: 8,
                gravity: 0.3,
                colors: const [
                  Colors.red,
                  Colors.amber,
                  Colors.green,
                  Colors.blue,
                  Colors.white,
                ],
              ),
            ),
            if (_showReveal && _winnerNumber != null) _buildGrandReveal(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildSponsorStrip(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/astrapi_logo.PNG', height: 40),
          const SizedBox(width: 14),
          Container(width: 1, height: 30, color: Colors.white24),
          const SizedBox(width: 14),
          Image.asset('assets/vir-favicon.png', height: 32),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(ColorScheme scheme, int totalTickets, int poolSize) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, Colors.black, 0.55)!,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.directions_car_filled,
                size: 26,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                'ΚΛΗΡΩΣΗ ΑΥΤΟΚΙΝΗΤΟΥ',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.emoji_events, size: 22, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 8),
          if (totalTickets == 0)
            Text(
              'Πρόσθεσε πρώτα ομάδες λαχείων από το μενού',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _statChip(Icons.local_activity, 'Διαθέσιμα', '$poolSize'),
                const SizedBox(width: 8),
                _statChip(Icons.confirmation_number, 'Σύνολο', '$totalTickets'),
              ],
            ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            '$value $label',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawButton(ColorScheme scheme, int totalTickets, int poolSize) {
    final enabled = totalTickets != 0 && poolSize != 0 && !_isDrawing;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? _beginDrawFlow : null,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 240,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFFF3D97C),
                      scheme.primary,
                      Color.lerp(scheme.primary, scheme.secondary, 0.5)!,
                    ],
                  )
                : LinearGradient(
                    colors: [
                      scheme.surfaceContainerHighest,
                      scheme.surfaceContainerHighest,
                    ],
                  ),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.5),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isDrawing ? Icons.hourglass_top : Icons.flag,
                color: enabled ? Colors.black87 : scheme.outline,
              ),
              const SizedBox(width: 10),
              Text(
                _isDrawing ? 'Κληρώνεται...' : 'ΚΛΗΡΩΣΗ',
                style: TextStyle(
                  color: enabled ? Colors.black87 : scheme.outline,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExcludeToggle(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        secondary: Icon(Icons.block, color: scheme.primary, size: 20),
        title: const Text(
          'Εξαίρεση προηγούμενων νικητών',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        value: _excludePreviousWinners,
        onChanged: _isDrawing
            ? null
            : (v) => setState(() => _excludePreviousWinners = v),
      ),
    );
  }

  Widget _buildHistoryCard(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: _history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_events_outlined,
                    size: 20,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Δεν έχει γίνει καμία κλήρωση ακόμα',
                    style: TextStyle(color: scheme.outline, fontSize: 12),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history, size: 18, color: scheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Ιστορικό κληρώσεων',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: _clearHistory,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Καθαρισμός'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final entry = _history[index];
                      final medal = switch (index) {
                        0 => Colors.amber,
                        1 => const Color(0xFFC0C0C0),
                        2 => const Color(0xFFCD7F32),
                        _ => null,
                      };
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: medal != null
                              ? medal.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: medal != null
                              ? Border.all(color: medal.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onTap: () => _showProofDetails(entry),
                          leading: CircleAvatar(
                            backgroundColor:
                                medal ?? scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.emoji_events,
                              size: 18,
                              color: medal != null
                                  ? Colors.black87
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            '${entry.number}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat(
                                  'dd/MM/yyyy HH:mm',
                                ).format(entry.timestamp),
                                style: TextStyle(
                                  color: scheme.outline,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.verified_outlined,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildGrandReveal(ColorScheme scheme) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _dismissReveal,
        child: FadeTransition(
          opacity: _revealController,
          child: Container(
            color: Colors.black.withValues(alpha: 0.78),
            alignment: Alignment.center,
            child: ScaleTransition(
              scale: _revealScale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events,
                        color: Colors.amber.shade400,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'ΜΕΓΑΛΟΣ ΝΙΚΗΤΗΣ',
                        style: TextStyle(
                          color: Colors.amber.shade300,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.emoji_events,
                        color: Colors.amber.shade400,
                        size: 36,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      final glow = 0.5 + _glowController.value * 0.5;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: RadialGradient(
                            colors: [
                              Colors.amber.withValues(alpha: 0.35 * glow),
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withValues(
                                alpha: 0.55 * glow,
                              ),
                              blurRadius: 60 * glow,
                              spreadRadius: 10 * glow,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFF3C4),
                          Color(0xFFFFC93C),
                          Color(0xFFB8860B),
                        ],
                      ).createShader(rect),
                      child: Text(
                        '${_winnerNumber!}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 140,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Συγχαρητήρια στον νικητή του λαχείου!',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _history.isEmpty
                        ? null
                        : () => _showProofDetails(_history.first),
                    icon: const Icon(
                      Icons.verified_outlined,
                      size: 18,
                      color: Colors.amber,
                    ),
                    label: const Text(
                      'Απόδειξη Διαφάνειας',
                      style: TextStyle(color: Colors.amber),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.amber.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Πάτησε οπουδήποτε αλλού για να συνεχίσεις',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReel(ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _bounceController,
          builder: (context, child) {
            final bounce = _isDrawing
                ? sin(_bounceController.value * pi) * 6
                : 0.0;
            return Transform.translate(
              offset: Offset(0, -bounce),
              child: child,
            );
          },
          child: Icon(
            Icons.directions_car_filled,
            size: 28,
            color: scheme.primary,
            shadows: const [
              Shadow(
                color: Colors.black45,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _buildSlotMachine(scheme),
      ],
    );
  }

  Widget _buildSlotMachine(ColorScheme scheme) {
    final digitCount = _digitCount;
    final totalWidth = _cellWidth * digitCount + _reelGap * (digitCount - 1);
    final settled = !_isDrawing && _digitAnimations[0] != null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0c0a0d),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.35),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var pos = 0; pos < digitCount; pos++) ...[
                if (pos > 0) const SizedBox(width: _reelGap),
                _buildDigitColumn(pos, scheme),
              ],
            ],
          ),
          // Fixed payline marker across the middle row of every column.
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: totalWidth + 8,
              height: _cellHeight + 8,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(
                    color: settled
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: settled
                    ? [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitColumn(int pos, ColorScheme scheme) {
    final anim = _digitAnimations[pos];
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: _cellWidth,
        height: _cellHeight * 3,
        color: const Color(0xFF15121a),
        child: ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: anim == null
              ? Stack(
                  children: [
                    Positioned(
                      top: _cellHeight,
                      left: 0,
                      right: 0,
                      child: _slotCell(0, scheme, highlight: false),
                    ),
                  ],
                )
              : AnimatedBuilder(
                  animation: anim,
                  builder: (context, _) {
                    final v = anim.value;
                    final baseIndex = v.floor();
                    final locked =
                        _digitControllers[pos].status ==
                        AnimationStatus.completed;
                    return Stack(
                      children: [
                        for (var i = baseIndex - 1; i <= baseIndex + 2; i++)
                          Positioned(
                            top: _cellHeight * (1 + i - v),
                            left: 0,
                            right: 0,
                            child: _slotCell(
                              ((i % 10) + 10) % 10,
                              scheme,
                              highlight: locked && i == baseIndex,
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _slotCell(int number, ColorScheme scheme, {required bool highlight}) {
    return Container(
      width: _cellWidth,
      height: _cellHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: highlight ? scheme.onPrimary : Colors.white70,
        ),
      ),
    );
  }
}
