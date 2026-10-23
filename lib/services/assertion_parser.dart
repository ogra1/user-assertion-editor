import 'dart:convert';

/// A parsed (signed or unsigned) assertion from its text form.
class ParsedAssertion {
  final Map<String, dynamic> headers;
  final String signature; // '' when unsigned
  final String raw;

  const ParsedAssertion(
      {required this.headers, required this.signature, required this.raw});

  String? operator [](String key) => headers[key] as String?;
}

class AssertionParseException implements Exception {
  final String message;
  const AssertionParseException(this.message);
  @override
  String toString() => message;
}

/// Parses signed assertion text (headers + blank line + signature) and the
/// JSON headers fed to `snap sign`.
class AssertionParser {
  /// Parses one or more concatenated signed assertions (a "chain").
  ///
  /// * If [text] is a JSON object (the unsigned header form fed to
  ///   `snap sign`), it is returned as a single unsigned assertion.
  /// * Otherwise each assertion begins at a top-level `type: <name>` header.
  ///   Blocks are separated at the last blank line before the next `type:`
  ///   header, so a signature block and its trailing blanks are kept with the
  ///   assertion they belong to. Returns them in file order.
  static List<ParsedAssertion> parseChain(String text) {
    final trimmed = text.trim().replaceAll('\r\n', '\n');
    if (trimmed.isEmpty) {
      throw const AssertionParseException('No assertion found in input.');
    }
    if (trimmed.startsWith('{')) {
      return [parseOne(trimmed)];
    }

    // Find top-level "type: " headers (signature blocks are base64, so a
    // top-level "type: " line can only be a header).
    final lines = trimmed.split('\n');
    final starts = <int>[];
    var offset = 0;
    for (final line in lines) {
      if (line.startsWith('type: ')) starts.add(offset);
      offset += line.length + 1;
    }
    if (starts.isEmpty) {
      return [parseOne(trimmed)];
    }

    final blocks = <String>[];
    for (var i = 0; i < starts.length; i++) {
      final seg = i + 1 < starts.length
          ? trimmed.substring(starts[i], starts[i + 1])
          : trimmed.substring(starts[i]);
      // Trim trailing blank lines so the next header is not swallowed.
      var endIdx = seg.length;
      while (endIdx > 0 && seg[endIdx - 1] == '\n') {
        endIdx--;
      }
      final block = seg.substring(0, endIdx).trim();
      if (block.isNotEmpty) blocks.add(block);
    }
    return blocks.map(parseOne).toList();
  }

  static ParsedAssertion parseOne(String text) {
    final normalized = text.trim().replaceAll('\r\n', '\n');

    // JSON header (unsigned) vs signed text form.
    if (normalized.startsWith('{')) {
      final decoded = jsonDecode(normalized);
      if (decoded is! Map) {
        throw const AssertionParseException('JSON header is not an object.');
      }
      return ParsedAssertion(
          headers: {
            for (final e in decoded.entries) e.key as String: e.value,
          },
          signature: '',
          raw: normalized);
    }

    final blankIdx = normalized.indexOf('\n\n');
    if (blankIdx < 0) {
      // Could still be a bare header block (unsigned text form).
      final headers = _parseHeaders(normalized);
      return ParsedAssertion(headers: headers, signature: '', raw: normalized);
    }

    final headerBlock = normalized.substring(0, blankIdx);
    final signature = normalized.substring(blankIdx + 2).trim();
    if (signature.isEmpty) {
      throw const AssertionParseException('Empty signature block.');
    }
    final headers = _parseHeaders(headerBlock);
    if (headers['type'] == null) {
      throw const AssertionParseException('Missing "type" header.');
    }
    return ParsedAssertion(
        headers: headers, signature: signature, raw: normalized);
  }

  static Map<String, dynamic> _parseHeaders(String block) {
    final headers = <String, dynamic>{};
    final lines = block.split('\n');
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
        i++;
        continue;
      }
      final colon = line.indexOf(':');
      if (colon <= 0) {
        i++;
        continue;
      }
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      if (value.isEmpty) {
        // List header: collect following "  - item" lines.
        final items = <String>[];
        var j = i + 1;
        while (j < lines.length &&
            (lines[j].startsWith('  ') || lines[j].startsWith('\t'))) {
          final item = lines[j].trim();
          if (item.startsWith('- ')) {
            items.add(item.substring(2).trim());
          }
          j++;
        }
        headers[key] = items;
        i = j;
        continue;
      }
      headers[key] = value;
      i++;
    }
    return headers;
  }
}
