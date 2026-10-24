import 'package:flutter/material.dart';

/// Shared [TextField] styling so every wizard form looks consistent and
/// native (outlined, 4px radius, dense padding) — matching the sibling
/// gadget-editor / model-builder inputs.
class FormTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final String? Function(String?)? validator;
  final bool obscure;
  final bool readOnly;
  /// A simple leading icon (non-interactive).
  final IconData? prefixIcon;
  /// A full leading [Widget] (e.g. a tappable icon button). Takes priority
  /// over [prefixIcon] when both are provided.
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  const FormTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.validator,
    this.obscure = false,
    this.readOnly = false,
    this.prefixIcon,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderSide: BorderSide(color: scheme.outline, width: 1),
      borderRadius: BorderRadius.circular(4),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          readOnly: readOnly,
          maxLines: maxLines,
          minLines: maxLines == 1 ? null : 1,
          keyboardType: keyboardType,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          onTap: onTap,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            helperMaxLines: 3,
            prefixIcon: prefix ??
                (prefixIcon != null ? Icon(prefixIcon) : null),
            suffixIcon: suffix,
            isDense: true,
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: scheme.primary, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}
