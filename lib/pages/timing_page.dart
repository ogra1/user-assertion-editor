import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../models/wizard_state.dart';
import '../widgets/form_fields.dart';

/// Step 3 — the validity window and user lifetime.
class TimingPage extends StatefulWidget {
  final WizardState state;
  const TimingPage({super.key, required this.state});

  @override
  State<TimingPage> createState() => _TimingPageState();
}

class _TimingPageState extends State<TimingPage> {
  final _since = TextEditingController();
  final _until = TextEditingController();

  @override
  void initState() {
    super.initState();
    final u = widget.state.model;
    if (u.since != null) _since.text = u.since!.toIso8601String();
    if (u.until != null) _until.text = u.until!.toIso8601String();
  }

  @override
  void dispose() {
    _since.dispose();
    _until.dispose();
    super.dispose();
  }

  void _commit() {
    final u = widget.state.model;
    final s = _since.text.trim();
    final t = _until.text.trim();
    u.since = s.isEmpty ? null : DateTime.tryParse(s)?.toUtc();
    u.until = t.isEmpty ? null : DateTime.tryParse(t)?.toUtc();
    widget.state.refresh();
  }

  /// Opens the date picker bound to the calendar icon. The picked date
  /// replaces only the date part; the time-of-day of the current value is
  /// kept (or the current time is used when the field is empty).
  Future<void> _pick(bool since) async {
    final now = DateTime.now().toLocal();
    final current = since
        ? (widget.state.model.since ?? now).toLocal()
        : (widget.state.model.until ??
            now.add(const Duration(days: 30)))
            .toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: since ? 'Pick the start date' : 'Pick the end date',
      cancelText: 'Cancel',
      confirmText: 'OK',
    );
    if (picked == null) return;
    final withTime = DateTime(
        picked.year, picked.month, picked.day,
        current.hour, current.minute, current.second);
    setState(() {
      (since ? _since : _until).text = withTime.toUtc().toIso8601String();
    });
    _commit();
  }

  void _applyWindow() {
    final now = DateTime.now().toUtc();
    setState(() {
      _since.text = now.toIso8601String();
      _until.text = now.add(const Duration(days: 30)).toIso8601String();
    });
    _commit();
  }

  void _applyYear() {
    final now = DateTime.now().toUtc();
    setState(() {
      _since.text = now.toIso8601String();
      _until.text = now.add(const Duration(days: 365)).toIso8601String();
    });
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.state.model;

    final window = (u.since != null && u.until != null)
        ? u.until!.difference(u.since!)
        : null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Timing', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'When may the device create this user from the assertion?',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('Validity window'),
          child: Column(
            children: [
              // Two-column date grid: "Valid from" and "Valid until" share a
              // row (same pattern as the User page identity grid).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Valid from (since) *',
                      controller: _since,
                      onPick: () => _pick(true),
                      onChanged: (_) => _commit(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DateField(
                      label: 'Valid until (until) *',
                      controller: _until,
                      onPick: () => _pick(false),
                      onChanged: (_) => _commit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (window != null) ...[
                    Icon(YaruIcons.calendar,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      'Valid for ${_fmtDuration(window)}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                  ],
                  OutlinedButton(
                    onPressed: _applyWindow,
                    child: const Text('Now → +30 days'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _applyYear,
                    child: const Text('Now → +1 year'),
                  ),
                ],
              ),
              if (!u.hasModels && window != null && window.inDays > 365)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No models set: snapd limits global assertions to 365 '
                    'days. Add a model (Device step) or shorten the window.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        YaruSection(
          headline: const Text('User lifetime'),
          child: Column(
            children: [
              YaruCheckboxListTile(
                title:
                    const Text('Remove the user when the assertion expires'),
                subtitle: Text(
                  'Sets user-presence: until-expiration. The account is deleted '
                  'at "Valid until" instead of staying. Requires a password and '
                  'an "until" date.',
                ),
                value: u.userUntilExpiration,
                onChanged: (v) {
                  u.userUntilExpiration = v ?? false;
                  widget.state.refresh();
                },
              ),
              if (u.userUntilExpiration && !u.hasPassword)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    'A password is required for this option — set one in the '
                    'User step.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmtDuration(Duration d) {
    final days = d.inDays;
    String dayWord(int n) => n == 1 ? 'day' : 'days';
    if (days < 365) return '$days ${dayWord(days)}';
    final years = days ~/ 365;
    final rem = days % 365;
    final yearWord = years == 1 ? '1 year' : '$years years';
    return rem == 0 ? yearWord : '$yearWord, $rem ${dayWord(rem)}';
  }
}

/// A validity date input: an editable RFC 3339 text field with a calendar
/// icon that opens the date picker. The field itself stays fully
/// editable — clicking the icon (not the field) is what pops the picker, so
/// the timestamp can be typed or adjusted by hand.
class _DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onPick;
  final ValueChanged<String>? onChanged;

  const _DateField({
    required this.label,
    required this.controller,
    required this.onPick,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormTextField(
      label: label,
      controller: controller,
      hint: 'RFC 3339, e.g. 2026-10-23T12:00:00Z',
      // Tappable calendar at the *start* of the field. It is a separate
      // widget from the text input, so the picker is bound to the icon and
      // the timestamp itself stays fully editable.
      prefix: IconButton(
        icon: const Icon(YaruIcons.calendar),
        tooltip: 'Pick a date',
        onPressed: onPick,
      ),
      onChanged: onChanged,
    );
  }
}
