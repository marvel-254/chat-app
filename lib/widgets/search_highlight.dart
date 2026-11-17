import 'package:flutter/material.dart';

/// Renders [text] with occurrences of [query] highlighted.
class SearchHighlightText extends StatelessWidget {
  const SearchHighlightText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    required this.highlightStyle,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final String query;
  final TextStyle style;
  final TextStyle highlightStyle;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty || text.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = cleanQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + cleanQuery.length),
        style: highlightStyle,
      ));
      start = index + cleanQuery.length;
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
