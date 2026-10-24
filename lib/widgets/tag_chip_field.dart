import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

/// A comma-or-Enter driven list field rendered as chips with delete
/// buttons — used for models, serials, and SSH keys.
class TagChipField extends StatefulWidget {
  final String label;
  final String? hint;
  final String? helper;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String? Function(String)? validateEntry;
  final bool multiline;

  const TagChipField({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.hint,
    this.helper,
    this.validateEntry,
    this.multiline = false,
  });

  @override
  State<TagChipField> createState() => _TagChipFieldState();
}

class _TagChipFieldState extends State<TagChipField> {
  /// The in-progress entry. Deliberately NOT pushed to the parent until it
  /// is committed (Enter or comma), so a half-typed "abcdefg" never becomes
  /// seven chips.
  late final TextEditingController _controller = TextEditingController();
  String? _entryError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Watches for separators — always commas, plus newlines when the field is
  /// [multiline] — and commits the complete entries, leaving the trailing
  /// uncommitted part as the draft. Detecting the newline is what makes Enter
  /// work in a multiline field: a multiline TextField inserts a line break
  /// instead of firing onSubmitted, so the newline is handled right here.
  void _onTextChanged(String text) {
    final separators = widget.multiline ? RegExp(r'[,\n]') : RegExp(r',');
    final segments = text.split(separators);
    final draft = segments.removeLast();

    final added = <String>[];
    for (final s in segments) {
      final v = s.trim();
      if (v.isEmpty) continue;
      final err = widget.validateEntry?.call(v);
      if (err != null) {
        // Non-destructive: leave the user's text in the field so they can fix
        // it, and surface the error. Nothing commits this round.
        setState(() => _entryError = err);
        return;
      }
      added.add(v);
    }

    if (added.isNotEmpty) {
      widget.onChanged([...widget.values, ...added]);
      setState(() => _entryError = null);
    }

    // Strip the committed separators out of the field, leaving only the
    // in-progress draft (repositioned to its tail, matching the comma path).
    if (text != draft) {
      _controller.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    }
  }

  void _commit(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return;
    final err = widget.validateEntry?.call(v);
    if (err != null) {
      _controller.clear();
      setState(() => _entryError = err);
      return;
    }
    widget.onChanged([...widget.values, v]);
    // On success the caller owns the draft: the comma path has already
    // repositioned it to the tail, and the Enter path clears it first.
    setState(() => _entryError = null);
  }

  void _remove(int index) {
    final base = List.of(widget.values);
    if (index >= base.length) return;
    base.removeAt(index);
    widget.onChanged(base);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: _entryError != null
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).dividerColor,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < widget.values.length; i++)
                _Chip(
                  label: widget.values[i],
                  onRemove: () => _remove(i),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TextField(
                  controller: _controller,
                  style: widget.multiline
                      ? Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontFamily: 'monospace')
                      : null,
                  maxLines: widget.multiline ? 3 : 1,
                  minLines: widget.multiline ? 1 : null,
                  onChanged: _onTextChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: widget.hint ??
                        (widget.values.isEmpty ? widget.label : 'Add another\u2026'),
                    helperText: null,
                  ),
                  onSubmitted: (t) {
                    _controller.clear();
                    _commit(t);
                  },
                ),
              ),
            ],
          ),
        ),
        if (_entryError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(YaruIcons.error,
                    size: 14, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _entryError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              ],
            ),
          )
        else if (widget.helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.helper!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        if (widget.values.isEmpty && _controller.text.trim().isEmpty)
          const SizedBox.shrink(),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _Chip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
          IconButton(
            icon: const Icon(YaruIcons.trash, size: 14),
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            iconSize: 14,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
