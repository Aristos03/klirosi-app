import 'package:flutter/material.dart';

import '../models/ticket_range.dart';

class RangesScreen extends StatefulWidget {
  const RangesScreen({
    super.key,
    required this.ranges,
    required this.onChanged,
  });

  final List<TicketRange> ranges;
  final ValueChanged<List<TicketRange>> onChanged;

  @override
  State<RangesScreen> createState() => _RangesScreenState();
}

class _RangesScreenState extends State<RangesScreen> {
  final List<TicketRange> _ranges = [];

  @override
  void initState() {
    super.initState();
    _ranges.addAll(widget.ranges);
  }

  int get _totalTickets => _ranges.fold(0, (sum, r) => sum + r.count);

  void _persist() {
    widget.onChanged(_ranges);
  }

  Future<void> _openEditor({TicketRange? existing}) async {
    final result = await showDialog<TicketRange>(
      context: context,
      builder: (_) => _RangeEditorDialog(existing: existing),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final idx = _ranges.indexWhere((r) => r.id == existing.id);
        _ranges[idx] = result;
      } else {
        _ranges.add(result);
      }
      _ranges.sort((a, b) => a.start.compareTo(b.start));
    });
    _persist();
  }

  Future<void> _delete(TicketRange range) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Διαγραφή ομάδας'),
        content: Text(
          'Να διαγραφεί η ομάδα "${range.label.isEmpty ? '${range.start}-${range.end}' : range.label}";',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Άκυρο'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Διαγραφή'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _ranges.removeWhere((r) => r.id == range.id));
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ομάδες Λαχείων'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Νέα ομάδα'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primaryContainer,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Σύνολο λαχείων',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$_totalTickets',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _ranges.isEmpty
                ? Center(
                    child: Text(
                      'Δεν έχεις προσθέσει ομάδες ακόμα.\nΠάτησε "Νέα ομάδα" για να ξεκινήσεις.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: _ranges.length,
                    itemBuilder: (context, index) {
                      final range = _ranges[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${index + 1}'),
                          ),
                          title: Text(
                            range.label.isEmpty
                                ? '${range.start} - ${range.end}'
                                : range.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            range.label.isEmpty
                                ? '${range.count} λαχεία'
                                : '${range.start} - ${range.end}  ·  ${range.count} λαχεία',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _openEditor(existing: range),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(range),
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
}

class _RangeEditorDialog extends StatefulWidget {
  const _RangeEditorDialog({this.existing});

  final TicketRange? existing;

  @override
  State<_RangeEditorDialog> createState() => _RangeEditorDialogState();
}

class _RangeEditorDialogState extends State<_RangeEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _labelController =
      TextEditingController(text: widget.existing?.label ?? '');
  late final _startController = TextEditingController(
    text: widget.existing != null ? '${widget.existing!.start}' : '',
  );
  late final _endController = TextEditingController(
    text: widget.existing != null ? '${widget.existing!.end}' : '',
  );

  @override
  void dispose() {
    _labelController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final start = int.parse(_startController.text.trim());
    final end = int.parse(_endController.text.trim());
    final result = TicketRange(
      id: widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      label: _labelController.text.trim(),
      start: start,
      end: end,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Νέα ομάδα λαχείων' : 'Επεξεργασία ομάδας'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Ετικέτα (προαιρετικό)',
                hintText: 'π.χ. Βιβλίο Α',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Από'),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null) return 'Αριθμός';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Έως'),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null) return 'Αριθμός';
                      final start = int.tryParse(_startController.text.trim());
                      if (start != null && n < start) return 'Έως ≥ Από';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Άκυρο'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
