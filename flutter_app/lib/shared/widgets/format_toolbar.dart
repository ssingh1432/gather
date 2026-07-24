import 'package:flutter/material.dart';

/// A row of formatting buttons that wrap/prefix the current selection in
/// [controller] with lightweight markdown syntax. Deliberately avoids a
/// heavyweight rich-text-editor package (e.g. flutter_quill): posts are
/// still stored as plain `text_content` strings, so this keeps every other
/// read path (feed cards, notifications, search, quote previews) working
/// unchanged — they just render the markers via [MarkdownLiteText] instead
/// of plain Text.
class FormatToolbar extends StatelessWidget {
  const FormatToolbar({super.key, required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  void _wrapSelection(String marker, {String? endMarker}) {
    final end = endMarker ?? marker;
    final sel = controller.selection;
    final text = controller.text;

    if (!sel.isValid || sel.isCollapsed) {
      // Nothing selected — insert an empty pair and place the cursor
      // between the markers so the user can just start typing.
      final insertAt = sel.isValid ? sel.start : text.length;
      final newText = text.replaceRange(insertAt, insertAt, '$marker$end');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: insertAt + marker.length),
      );
      onChanged(newText);
      return;
    }

    final selected = text.substring(sel.start, sel.end);
    final wrapped = '$marker$selected$end';
    final newText = text.replaceRange(sel.start, sel.end, wrapped);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + wrapped.length),
    );
    onChanged(newText);
  }

  void _prefixLines(String prefix) {
    final sel = controller.selection;
    final text = controller.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;

    // Extend to the start/end of the enclosing lines so a partial
    // selection still prefixes whole lines.
    final lineStart = text.lastIndexOf('\n', start > 0 ? start - 1 : 0) + 1;
    var lineEnd = text.indexOf('\n', end);
    if (lineEnd == -1) lineEnd = text.length;

    final block = text.substring(lineStart, lineEnd);
    final prefixed = block.isEmpty
        ? prefix
        : block.split('\n').map((l) => l.startsWith(prefix) ? l : '$prefix$l').join('\n');

    final newText = text.replaceRange(lineStart, lineEnd, prefixed);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + prefixed.length),
    );
    onChanged(newText);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: 'Bold',
          icon: const Icon(Icons.format_bold, size: 20),
          onPressed: () => _wrapSelection('**'),
        ),
        IconButton(
          tooltip: 'Italic',
          icon: const Icon(Icons.format_italic, size: 20),
          onPressed: () => _wrapSelection('_'),
        ),
        IconButton(
          tooltip: 'Underline',
          icon: const Icon(Icons.format_underline, size: 20),
          onPressed: () => _wrapSelection('++'),
        ),
        IconButton(
          tooltip: 'Code',
          icon: const Icon(Icons.code, size: 20),
          onPressed: () => _wrapSelection('`'),
        ),
        IconButton(
          tooltip: 'Quote',
          icon: const Icon(Icons.format_quote, size: 20),
          onPressed: () => _prefixLines('> '),
        ),
        IconButton(
          tooltip: 'Bullet list',
          icon: const Icon(Icons.format_list_bulleted, size: 20),
          onPressed: () => _prefixLines('- '),
        ),
      ],
    );
  }
}

/// Renders text containing the markers written by [FormatToolbar]:
/// `**bold**`, `_italic_`, `++underline++`, `` `code` ``, `> quote` lines,
/// and `- bullet` lines. Falls back to plain text for anything unmatched,
/// so existing posts (written before this feature existed) render exactly
/// as before.
class MarkdownLiteText extends StatelessWidget {
  const MarkdownLiteText(this.data, {super.key, this.style, this.maxLines, this.overflow});

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  static final _inlinePattern = RegExp(r'(\*\*.+?\*\*|_.+?_|\+\+.+?\+\+|`.+?`)');

  List<InlineSpan> _parseInline(String line, TextStyle base) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inlinePattern.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      final token = m.group(0)!;
      if (token.startsWith('**')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (token.startsWith('++')) {
        spans.add(TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(decoration: TextDecoration.underline),
        ));
      } else if (token.startsWith('`')) {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(fontFamily: 'monospace', backgroundColor: Colors.black12),
        ));
      } else {
        spans.add(TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final lines = data.split('\n');

    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: base,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const TextSpan(text: '\n'),
            if (lines[i].startsWith('> '))
              TextSpan(
                text: lines[i].substring(2),
                style: base.copyWith(color: base.color?.withValues(alpha: 0.65), fontStyle: FontStyle.italic),
              )
            else if (lines[i].startsWith('- '))
              TextSpan(children: [
                const TextSpan(text: '•  '),
                ..._parseInline(lines[i].substring(2), base),
              ])
            else
              TextSpan(children: _parseInline(lines[i], base)),
          ],
        ],
      ),
    );
  }
}
