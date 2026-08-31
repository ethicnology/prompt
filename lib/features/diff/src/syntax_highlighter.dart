import 'package:flutter/material.dart';

abstract interface class SyntaxHighlighter {
  List<InlineSpan> highlight(String source, TextStyle base, Color accent);
}

class BasicSyntaxHighlighter implements SyntaxHighlighter {
  const BasicSyntaxHighlighter();

  @override
  List<InlineSpan> highlight(String source, TextStyle base, Color accent) {
    final result = <InlineSpan>[];
    final pattern = RegExp(
      r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|//.*|#.*|\b\d+(?:\.\d+)?\b|\b(?:class|const|final|return|void|var|function|if|else|for|true|false|null|import|extends|async|await)\b)''',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(source)) {
      if (match.start > cursor) {
        result.add(
          TextSpan(text: source.substring(cursor, match.start), style: base),
        );
      }
      final value = match.group(0)!;
      final color = value.startsWith('//') || value.startsWith('#')
          ? Colors.grey
          : value.startsWith('"') || value.startsWith("'")
          ? Colors.orange
          : accent;
      result.add(
        TextSpan(
          text: value,
          style: base.copyWith(color: color),
        ),
      );
      cursor = match.end;
    }
    if (cursor < source.length) {
      result.add(TextSpan(text: source.substring(cursor), style: base));
    }
    return result;
  }
}

SyntaxHighlighter highlighterForPath(String path) {
  final lower = path.toLowerCase();
  if (RegExp(r'\.(dart|json|ya?ml|sh|bash|js|jsx|ts|tsx)$').hasMatch(lower)) {
    return const BasicSyntaxHighlighter();
  }
  return const _PlainHighlighter();
}

class _PlainHighlighter implements SyntaxHighlighter {
  const _PlainHighlighter();
  @override
  List<InlineSpan> highlight(String source, TextStyle base, Color accent) =>
      <InlineSpan>[TextSpan(text: source, style: base)];
}
