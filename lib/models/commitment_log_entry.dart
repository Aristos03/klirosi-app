/// A permanent, append-only record of every commitment hash the app has
/// ever shown -- including ones that were cancelled and never used for an
/// actual draw. This makes it possible to prove that no attempts were
/// silently discarded in search of a more favourable outcome.
class CommitmentLogEntry {
  final DateTime timestamp;
  final String commitmentHash;
  final String status; // 'shown', 'used', 'cancelled'
  final int? drawNumber;

  CommitmentLogEntry({
    required this.timestamp,
    required this.commitmentHash,
    required this.status,
    this.drawNumber,
  });

  CommitmentLogEntry copyWith({String? status, int? drawNumber}) =>
      CommitmentLogEntry(
        timestamp: timestamp,
        commitmentHash: commitmentHash,
        status: status ?? this.status,
        drawNumber: drawNumber ?? this.drawNumber,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'commitmentHash': commitmentHash,
        'status': status,
        'drawNumber': drawNumber,
      };

  factory CommitmentLogEntry.fromJson(Map<String, dynamic> json) =>
      CommitmentLogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        commitmentHash: json['commitmentHash'] as String,
        status: json['status'] as String,
        drawNumber: json['drawNumber'] as int?,
      );
}
