import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

/// Renders the small Markdown subset used in conversation text without
/// interpreting HTML or accepting arbitrary link schemes.
class BasicMarkdownText extends StatelessWidget {
  const BasicMarkdownText({required this.text, this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          _buildBlock(context, blocks[index]),
          if (index != blocks.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _MarkdownBlock block) {
    final theme = Theme.of(context);
    return switch (block) {
      _HeadingBlock(:final text, :final level) => Semantics(
        header: true,
        child: SelectableText.rich(
          TextSpan(
            style: _headingStyle(theme, level),
            children: _inlineSpans(context, text, _headingStyle(theme, level)),
          ),
        ),
      ),
      _CodeBlock(:final text) => Semantics(
        label: 'Code block',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: theme.colorScheme.surfaceContainerHigh,
          child: SelectableText(
            text,
            style: style?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ),
      _TextBlock(:final text) => SelectableText.rich(
        TextSpan(style: style, children: _inlineSpans(context, text, style)),
      ),
    };
  }

  TextStyle? _headingStyle(ThemeData theme, int level) {
    final base = switch (level) {
      1 => theme.textTheme.headlineSmall,
      2 => theme.textTheme.titleLarge,
      _ => theme.textTheme.titleMedium,
    };
    return base?.copyWith(color: style?.color);
  }

  List<InlineSpan> _inlineSpans(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final spans = <InlineSpan>[];
    var index = 0;
    while (index < text.length) {
      if (text.startsWith('`', index)) {
        final end = text.indexOf('`', index + 1);
        if (end != -1) {
          spans.add(
            TextSpan(
              text: text.substring(index + 1, end),
              style: (style ?? const TextStyle()).copyWith(
                fontFamily: 'monospace',
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHigh,
              ),
            ),
          );
          index = end + 1;
          continue;
        }
      }
      if (text.startsWith('**', index)) {
        final end = text.indexOf('**', index + 2);
        if (end != -1) {
          spans.add(
            TextSpan(
              text: text.substring(index + 2, end),
              style: (style ?? const TextStyle()).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          );
          index = end + 2;
          continue;
        }
      }
      if (text.startsWith('[', index)) {
        final labelEnd = text.indexOf('](', index + 1);
        if (labelEnd != -1) {
          final urlEnd = text.indexOf(')', labelEnd + 2);
          if (urlEnd != -1) {
            final url = _safeHttpUri(text.substring(labelEnd + 2, urlEnd));
            if (url != null) {
              spans.add(
                _linkSpan(
                  context,
                  text.substring(index + 1, labelEnd),
                  url,
                  style,
                ),
              );
              index = urlEnd + 1;
              continue;
            }
          }
        }
      }
      final bareUrl = _bareUrlAt(text, index);
      if (bareUrl != null) {
        spans.add(_linkSpan(context, bareUrl.text, bareUrl.uri, style));
        index += bareUrl.text.length;
        continue;
      }
      final next = _nextMarkup(text, index + 1);
      spans.add(TextSpan(text: text.substring(index, next)));
      index = next;
    }
    return spans;
  }

  WidgetSpan _linkSpan(
    BuildContext context,
    String label,
    Uri uri,
    TextStyle? style,
  ) {
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary,
    );
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Link(
        uri: uri,
        target: LinkTarget.blank,
        builder: (context, followLink) => Semantics(
          link: true,
          label: '$label, link',
          child: InkWell(
            onTap: followLink,
            child: Text(label, style: linkStyle),
          ),
        ),
      ),
    );
  }
}

sealed class _MarkdownBlock {
  const _MarkdownBlock();
}

class _TextBlock extends _MarkdownBlock {
  const _TextBlock(this.text);

  final String text;
}

class _HeadingBlock extends _MarkdownBlock {
  const _HeadingBlock(this.text, this.level);

  final String text;
  final int level;
}

class _CodeBlock extends _MarkdownBlock {
  const _CodeBlock(this.text);

  final String text;
}

List<_MarkdownBlock> _parseBlocks(String source) {
  final blocks = <_MarkdownBlock>[];
  final lines = source.split('\n');
  final text = <String>[];
  List<String>? code;

  void flushText() {
    if (text.isNotEmpty) {
      blocks.add(_TextBlock(text.join('\n')));
      text.clear();
    }
  }

  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) {
      if (code == null) {
        flushText();
        code = <String>[];
      } else {
        blocks.add(_CodeBlock(code.join('\n')));
        code = null;
      }
      continue;
    }
    if (code case final codeLines?) {
      codeLines.add(line);
      continue;
    }
    final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(line);
    if (heading != null) {
      flushText();
      blocks.add(_HeadingBlock(heading.group(2)!, heading.group(1)!.length));
    } else {
      text.add(line);
    }
  }
  if (code != null) {
    text.add('```');
    text.addAll(code);
  }
  flushText();
  return blocks.isEmpty ? const [_TextBlock('')] : blocks;
}

int _nextMarkup(String text, int start) {
  for (var index = start; index < text.length; index++) {
    if (text[index] == '`' ||
        text[index] == '[' ||
        text.startsWith('**', index) ||
        text.startsWith('http://', index) ||
        text.startsWith('https://', index)) {
      return index;
    }
  }
  return text.length;
}

({String text, Uri uri})? _bareUrlAt(String text, int start) {
  if (!text.startsWith('http://', start) &&
      !text.startsWith('https://', start)) {
    return null;
  }
  var end = start;
  while (end < text.length && !RegExp(r'[\s\]\[<>]').hasMatch(text[end])) {
    end++;
  }
  var candidate = text.substring(start, end);
  while (candidate.endsWith('.') ||
      candidate.endsWith(',') ||
      candidate.endsWith(')')) {
    candidate = candidate.substring(0, candidate.length - 1);
  }
  final uri = _safeHttpUri(candidate);
  return uri == null ? null : (text: candidate, uri: uri);
}

Uri? _safeHttpUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}
