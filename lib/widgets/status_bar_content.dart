import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import '../services/status_bar_service.dart';
import '../theme/status_colors.dart';
import 'truncating_tooltip_text.dart';

/// The active status message, rendered in the footer's left slot.
///
/// Must be a fresh (non-const) widget on every build: an identical const
/// instance would short-circuit the element update and freeze the content
/// on the first message.
class StatusBarContent extends StatelessWidget {
  const StatusBarContent({super.key});

  @override
  Widget build(BuildContext context) {
    final message = StatusBarService.instance.current;
    if (message == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (message.severity) {
      StatusSeverity.error => (YaruIcons.error, StatusColors.error),
      StatusSeverity.success => (YaruIcons.ok, StatusColors.success),
      StatusSeverity.info => (YaruIcons.information, scheme.onSurface),
    };

    final isLong = message.text.length > 90;

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: TruncatingTooltipText(
            message.text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: message.severity == StatusSeverity.info
                      ? scheme.onSurface
                      : color,
                ),
          ),
        ),
        if (isLong)
          TextButton(
            onPressed: () => _showDetails(context, message.text),
            child: const Text('Details\u2026'),
          ),
        if (message.severity == StatusSeverity.error)
          IconButton(
            icon: const Icon(YaruIcons.window_close, size: 14),
            tooltip: 'Dismiss (or press Escape)',
            onPressed: StatusBarService.instance.clear,
            visualDensity: VisualDensity.compact,
            iconSize: 14,
          ),
      ],
    );
  }

  void _showDetails(BuildContext context, String text) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Details'),
        content: SizedBox(
          width: 560,
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: Theme.of(dialogContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
