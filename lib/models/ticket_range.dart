class TicketRange {
  final String id;
  final String label;
  final int start;
  final int end;

  TicketRange({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
  });

  int get count => end - start + 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'start': start,
        'end': end,
      };

  factory TicketRange.fromJson(Map<String, dynamic> json) => TicketRange(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        start: json['start'] as int,
        end: json['end'] as int,
      );
}
