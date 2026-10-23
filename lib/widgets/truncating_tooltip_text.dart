import 'package:flutter/material.dart';

/// A single-line [Text] that truncates with an ellipsis and shows the full
/// content in a tooltip on hover (only when the text is long enough to be
/// worth truncating).
class TruncatingTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const TruncatingTooltipText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final line = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (text.length <= 60) return line;
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 400),
      child: line,
    );
  }
}
