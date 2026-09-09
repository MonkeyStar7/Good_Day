class GoodDayGoal {
  const GoodDayGoal({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.colorValue,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;
  final int colorValue;
  final DateTime createdAt;

  GoodDayGoal update({
    required String name,
    required String description,
    required int colorValue,
  }) {
    return GoodDayGoal(
      id: id,
      name: _singleLine(name).trim(),
      description: _singleLine(description).trim(),
      colorValue: colorValue,
      createdAt: createdAt,
    );
  }

  String toMarkdown() {
    final color = colorValue.toRadixString(16).padLeft(8, '0').toUpperCase();
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('id: $id')
      ..writeln('created: ${createdAt.toIso8601String()}')
      ..writeln('color: $color')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${_singleLine(name).trim()}');
    if (description.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('> ${_singleLine(description).trim()}');
    }
    return buffer.toString();
  }

  factory GoodDayGoal.fromMarkdown(String source) {
    final parsed = _parseDocument(source);
    final id = parsed.values['id'];
    final created = DateTime.tryParse(parsed.values['created'] ?? '');
    final color = int.tryParse(parsed.values['color'] ?? '', radix: 16);
    if (id == null || id.isEmpty || created == null || color == null) {
      throw const FormatException('Invalid goal metadata.');
    }
    final description = parsed.bodyLines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.startsWith('> ') ? line.substring(2) : line)
        .join(' ')
        .trim();
    return GoodDayGoal(
      id: id,
      name: parsed.title,
      description: description,
      colorValue: color,
      createdAt: created,
    );
  }
}

_ParsedDocument _parseDocument(String source) {
  final lines = source.split(RegExp(r'\r?\n'));
  if (lines.isEmpty || lines.first.trim() != '---') {
    throw const FormatException('Missing Markdown front matter.');
  }
  final values = <String, String>{};
  var index = 1;
  for (; index < lines.length; index++) {
    final line = lines[index];
    if (line.trim() == '---') {
      index++;
      break;
    }
    final separator = line.indexOf(':');
    if (separator > 0) {
      values[line.substring(0, separator).trim()] = line
          .substring(separator + 1)
          .trim();
    }
  }
  var titleIndex = -1;
  for (var i = index; i < lines.length; i++) {
    if (lines[i].startsWith('# ')) {
      titleIndex = i;
      break;
    }
  }
  if (titleIndex == -1) throw const FormatException('Missing title.');
  return _ParsedDocument(
    values,
    lines[titleIndex].substring(2).trim(),
    lines.sublist(titleIndex + 1),
  );
}

class _ParsedDocument {
  const _ParsedDocument(this.values, this.title, this.bodyLines);

  final Map<String, String> values;
  final String title;
  final List<String> bodyLines;
}

String _singleLine(String value) =>
    value.replaceAll(RegExp(r'[\r\n]+'), ' ').trimRight();
