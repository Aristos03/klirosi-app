class DrawResult {
  final int number;
  final DateTime timestamp;

  // Provably-fair transparency record. Fields default to "unknown" values
  // for entries saved before this feature existed.
  final String seed;
  final String commitmentHash;
  final String audienceNumber;
  final String pressMoment;
  final int nonce;
  final int poolSize;
  final List<String> rangesSnapshot;
  final List<int> excludedNumbers;

  DrawResult({
    required this.number,
    required this.timestamp,
    this.seed = '',
    this.commitmentHash = '',
    this.audienceNumber = '',
    this.pressMoment = '',
    this.nonce = 0,
    this.poolSize = 0,
    this.rangesSnapshot = const [],
    this.excludedNumbers = const [],
  });

  bool get hasProof => seed.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'number': number,
        'timestamp': timestamp.toIso8601String(),
        'seed': seed,
        'commitmentHash': commitmentHash,
        'audienceNumber': audienceNumber,
        'pressMoment': pressMoment,
        'nonce': nonce,
        'poolSize': poolSize,
        'rangesSnapshot': rangesSnapshot,
        'excludedNumbers': excludedNumbers,
      };

  factory DrawResult.fromJson(Map<String, dynamic> json) => DrawResult(
        number: json['number'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
        seed: json['seed'] as String? ?? '',
        commitmentHash: json['commitmentHash'] as String? ?? '',
        audienceNumber: json['audienceNumber'] as String? ?? '',
        pressMoment: json['pressMoment'] as String? ?? '',
        nonce: json['nonce'] as int? ?? 0,
        poolSize: json['poolSize'] as int? ?? 0,
        rangesSnapshot: (json['rangesSnapshot'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        excludedNumbers: (json['excludedNumbers'] as List<dynamic>? ?? [])
            .map((e) => e as int)
            .toList(),
      );
}
