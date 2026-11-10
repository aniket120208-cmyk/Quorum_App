import 'dart:convert';
import 'dart:math' as math;

typedef DocMark = Map<String, dynamic>;

class RichRun {
  final String text;
  final List<DocMark> marks;
  const RichRun(this.text, [this.marks = const []]);
}

String _markKey(List<DocMark> marks) => marks.map(jsonEncode).join('|');

List<DocMark> _sortedMarks(Iterable<DocMark> marks) {
  final list = marks.map((m) => Map<String, dynamic>.from(m)).toList();
  list.sort((a, b) => a['type'].toString().compareTo(b['type'].toString()));
  return list;
}

DocText _normalize(List<RichRun> input) {
  final out = <RichRun>[];
  for (final r in input) {
    if (r.text.isEmpty) continue;
    if (out.isNotEmpty && _markKey(out.last.marks) == _markKey(r.marks)) {
      out[out.length - 1] = RichRun(out.last.text + r.text, out.last.marks);
    } else {
      out.add(r);
    }
  }
  return DocText(out);
}

({int prefix, int suffix}) commonEnds(String a, String b) {
  final shortest = math.min(a.length, b.length);
  var prefix = 0;
  while (prefix < shortest && a.codeUnitAt(prefix) == b.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  final maxSuffix = shortest - prefix;
  while (suffix < maxSuffix && a.codeUnitAt(a.length - 1 - suffix) == b.codeUnitAt(b.length - 1 - suffix)) {
    suffix++;
  }
  return (prefix: prefix, suffix: suffix);
}

class DocText {
  final List<RichRun> runs;

  const DocText(this.runs);

  static const DocText empty = DocText([]);
  factory DocText.plain(String value) => value.isEmpty ? empty : DocText([RichRun(value)]);
  String get text => runs.map((r) => r.text).join();
  int get length => runs.fold<int>(0, (sum, r) => sum + r.text.length);
  bool get isEmpty => runs.isEmpty;
  DocText operator +(DocText other) => _normalize([...runs, ...other.runs]);

  DocText slice(int start, int end) {
    final total = length;
    final from = math.min(math.max(start, 0), total);
    final to = math.min(math.max(end, from), total);
    if (from == to) return empty;
    final out = <RichRun>[];
    var pos = 0;
    for (final r in runs) {
      final runStart = pos;
      final runEnd = pos + r.text.length;
      pos = runEnd;
      if (runEnd <= from) continue;
      if (runStart >= to) break;
      final a = math.max(from, runStart) - runStart;
      final b = math.min(to, runEnd) - runStart;
      out.add(RichRun(r.text.substring(a, b), r.marks));
    }
    return DocText(out);
  }

  List<DocMark> marksAt(int index) {
    var pos = 0;
    for (final r in runs) {
      final end = pos + r.text.length;
      if (index >= pos && index < end) return r.marks;
      pos = end;
    }
    return const [];
  }

  DocText edited(String next) {
    final old = text;
    if (old == next) return this;
    final ends = commonEnds(old, next);
    final prefix = ends.prefix;
    final suffix = ends.suffix;
    final inserted = next.substring(prefix, next.length - suffix);
    final head = slice(0, prefix);
    final tail = slice(old.length - suffix, old.length);
    if (inserted.isEmpty) return head + tail;
    final marks = prefix > 0 ? marksAt(prefix - 1) : (old.isNotEmpty ? marksAt(0) : const <DocMark>[]);
    return head + DocText([RichRun(inserted, marks)]) + tail;
  }

  bool allHave(String type, int start, int end) {
    if (start >= end) return false;
    final range = slice(start, end);
    if (range.isEmpty) return false;
    return range.runs.every((r) => r.marks.any((m) => m['type'] == type));
  }

  String? linkIn(int start, int end) {
    final range = start >= end ? slice(start, start + 1) : slice(start, end);
    for (final r in range.runs) {
      for (final m in r.marks) {
        if (m['type'] == 'link' && m['attrs'] is Map) return (m['attrs'] as Map)['href']?.toString();
      }
    }
    return null;
  }

  DocText _mapRange(int start, int end, List<DocMark> Function(List<DocMark>) fn) {
    final head = slice(0, start);
    final mid = slice(start, end);
    final tail = slice(end, length);
    return head + DocText([for (final r in mid.runs) RichRun(r.text, fn(r.marks))]) + tail;
  }

  DocText withMark(DocMark mark, int start, int end) {
    if (start >= end) return this;
    return _mapRange(
      start,
      end,
      (marks) => _sortedMarks([...marks.where((m) => m['type'] != mark['type']), mark]),
    );
  }

  DocText withoutMark(String type, int start, int end) {
    if (start >= end) return this;
    return _mapRange(start, end, (marks) => marks.where((m) => m['type'] != type).toList());
  }

  DocText toggled(String type, int start, int end) {
    if (start >= end) return this;
    return allHave(type, start, end) ? withoutMark(type, start, end) : withMark({'type': type}, start, end);
  }

  List<Map<String, dynamic>> toNodes() {
    final out = <Map<String, dynamic>>[];
    for (final r in runs) {
      final parts = r.text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) out.add({'type': 'hardBreak'});
        if (parts[i].isEmpty) continue;
        out.add({
          'type': 'text',
          'text': parts[i],
          if (r.marks.isNotEmpty) 'marks': r.marks.map((m) => Map<String, dynamic>.from(m)).toList(),
        });
      }
    }
    return out;
  }

  static DocText? fromNodes(dynamic nodes) {
    if (nodes == null) return empty;
    if (nodes is! List) return null;
    final runs = <RichRun>[];
    for (final n in nodes) {
      if (n is! Map) return null;
      final type = n['type'];
      if (type == 'text') {
        final marks = n['marks'] is List
            ? _sortedMarks((n['marks'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)))
            : <DocMark>[];
        runs.add(RichRun((n['text'] ?? '').toString(), marks));
      } else if (type == 'hardBreak') {
        runs.add(const RichRun('\n'));
      } else {
        return null;
      }
    }
    return _normalize(runs);
  }
}

enum DocBlockType { paragraph, heading, bullet, ordered, task, quote, code, rule, opaque }

class DocBlock {
  DocBlock({
    String? id,
    required this.type,
    this.level = 1,
    this.depth = 0,
    this.checked = false,
    DocText? text,
    this.attrs,
    this.raw,
  })  : id = id ?? 'b${_next++}',
        text = text ?? DocText.empty;

  static int _next = 0;

  final String id;
  DocBlockType type;
  int level;
  int depth;
  bool checked;
  DocText text;
  Map<String, dynamic>? attrs;
  Map<String, dynamic>? raw;

  bool get isList => type == DocBlockType.bullet || type == DocBlockType.ordered || type == DocBlockType.task;
  bool get isEditable => type != DocBlockType.rule && type != DocBlockType.opaque;
  String get rawType => (raw?['type'] ?? 'content').toString();
}

class DocContent {
  DocContent._();

  static const Map<String, DocBlockType> _listTypes = {
    'bulletList': DocBlockType.bullet,
    'orderedList': DocBlockType.ordered,
    'taskList': DocBlockType.task,
  };

  static List<DocBlock> parse(dynamic content) {
    final blocks = <DocBlock>[];
    if (content is String) {
      final trimmed = content.trim();
      if (trimmed.startsWith('{')) {
        try {
          return parse(jsonDecode(trimmed));
        } catch (_) {}
      }
      for (final line in content.split('\n')) {
        blocks.add(DocBlock(type: DocBlockType.paragraph, text: DocText.plain(line)));
      }
    } else if (content is Map && content['content'] is List) {
      for (final n in content['content'] as List) {
        if (n is Map) _node(Map<String, dynamic>.from(n), 0, blocks);
      }
    }
    if (blocks.isEmpty) blocks.add(DocBlock(type: DocBlockType.paragraph));
    return blocks;
  }

  static DocBlock _opaque(Map<String, dynamic> node) => DocBlock(type: DocBlockType.opaque, raw: node);
  static void _node(Map<String, dynamic> n, int depth, List<DocBlock> out) {
    final type = n['type'];
    if (type == 'paragraph') {
      final t = DocText.fromNodes(n['content']);
      out.add(t == null ? _opaque(n) : DocBlock(type: DocBlockType.paragraph, text: t));
    } else if (type == 'heading') {
      final t = DocText.fromNodes(n['content']);
      final attrs = n['attrs'] is Map ? Map<String, dynamic>.from(n['attrs']) : <String, dynamic>{};
      final level = (int.tryParse((attrs['level'] ?? 1).toString()) ?? 1).clamp(1, 6).toInt();
      out.add(t == null ? _opaque(n) : DocBlock(type: DocBlockType.heading, level: level, text: t));
    } else if (type == 'codeBlock') {
      final buffer = StringBuffer();
      var plain = true;
      final content = n['content'];
      if (content is List) {
        for (final c in content) {
          if (c is Map && c['type'] == 'text') {
            buffer.write((c['text'] ?? '').toString());
          } else {
            plain = false;
          }
        }
      }
      out.add(plain
          ? DocBlock(
              type: DocBlockType.code,
              text: DocText.plain(buffer.toString()),
              attrs: n['attrs'] is Map ? Map<String, dynamic>.from(n['attrs']) : null,
            )
          : _opaque(n));
    } else if (type == 'blockquote') {
      final content = n['content'];
      if (content is List && content.length == 1 && content.first is Map && (content.first as Map)['type'] == 'paragraph') {
        final t = DocText.fromNodes((content.first as Map)['content']);
        out.add(t == null ? _opaque(n) : DocBlock(type: DocBlockType.quote, text: t));
      } else {
        out.add(_opaque(n));
      }
    } else if (type == 'horizontalRule') {
      out.add(DocBlock(type: DocBlockType.rule));
    } else if (_listTypes.containsKey(type)) {
      if (_simpleList(n)) {
        _emitList(n, depth, out);
      } else {
        out.add(_opaque(n));
      }
    } else {
      out.add(_opaque(n));
    }
  }

  static bool _simpleList(Map n) {
    final items = n['content'];
    if (items is! List || items.isEmpty) return false;
    for (final item in items) {
      if (item is! Map) return false;
      final t = item['type'];
      if (t != 'listItem' && t != 'taskItem') return false;
      final c = item['content'];
      if (c is! List || c.isEmpty) return false;
      final first = c.first;
      if (first is! Map || first['type'] != 'paragraph' || DocText.fromNodes(first['content']) == null) return false;
      for (final rest in c.skip(1)) {
        if (rest is! Map || !_listTypes.containsKey(rest['type']) || !_simpleList(rest)) return false;
      }
    }
    return true;
  }

  static void _emitList(Map<String, dynamic> n, int depth, List<DocBlock> out) {
    final kind = _listTypes[n['type']]!;
    for (final item in (n['content'] as List)) {
      final map = Map<String, dynamic>.from(item as Map);
      final attrs = map['attrs'] is Map ? Map<String, dynamic>.from(map['attrs']) : <String, dynamic>{};
      final content = map['content'] as List;
      final first = Map<String, dynamic>.from(content.first as Map);
      out.add(DocBlock(
        type: kind,
        depth: depth,
        checked: attrs['checked'] == true,
        text: DocText.fromNodes(first['content']) ?? DocText.empty,
      ));
      for (final rest in content.skip(1)) {
        _emitList(Map<String, dynamic>.from(rest as Map), depth + 1, out);
      }
    }
  }

  static Map<String, dynamic> serialize(List<DocBlock> blocks) {
    final nodes = <Map<String, dynamic>>[];
    final depths = _depths(blocks);
    var i = 0;
    while (i < blocks.length) {
      final b = blocks[i];
      if (b.isList) {
        i = _writeList(blocks, depths, i, 0, nodes);
      } else {
        nodes.add(_blockNode(b));
        i++;
      }
    }
    if (nodes.isEmpty) nodes.add({'type': 'paragraph'});
    return {'type': 'doc', 'content': nodes};
  }

  static List<int> _depths(List<DocBlock> blocks) {
    final out = <int>[];
    var prev = -1;
    for (final b in blocks) {
      if (!b.isList) {
        out.add(0);
        prev = -1;
        continue;
      }
      final d = math.min(math.max(b.depth, 0), prev + 1);
      out.add(d);
      prev = d;
    }
    return out;
  }

  static String _listName(DocBlockType t) {
    switch (t) {
      case DocBlockType.ordered:
        return 'orderedList';
      case DocBlockType.task:
        return 'taskList';
      default:
        return 'bulletList';
    }
  }

  static int _writeList(List<DocBlock> b, List<int> d, int start, int depth, List<Map<String, dynamic>> out) {
    final kind = b[start].type;
    final items = <Map<String, dynamic>>[];
    var i = start;
    while (i < b.length && b[i].isList && d[i] >= depth) {
      if (d[i] > depth) {
        final nested = <Map<String, dynamic>>[];
        i = _writeList(b, d, i, d[i], nested);
        (items.last['content'] as List).addAll(nested);
        continue;
      }
      if (b[i].type != kind) break;
      items.add({
        'type': kind == DocBlockType.task ? 'taskItem' : 'listItem',
        if (kind == DocBlockType.task) 'attrs': {'checked': b[i].checked},
        'content': [_paragraph(b[i].text)],
      });
      i++;
    }
    out.add({'type': _listName(kind), 'content': items});
    return i;
  }

  static Map<String, dynamic> _paragraph(DocText t) {
    final nodes = t.toNodes();
    return {'type': 'paragraph', if (nodes.isNotEmpty) 'content': nodes};
  }

  static Map<String, dynamic> _blockNode(DocBlock b) {
    switch (b.type) {
      case DocBlockType.heading:
        final nodes = b.text.toNodes();
        return {
          'type': 'heading',
          'attrs': {'level': b.level},
          if (nodes.isNotEmpty) 'content': nodes,
        };
      case DocBlockType.quote:
        return {
          'type': 'blockquote',
          'content': [_paragraph(b.text)],
        };
      case DocBlockType.code:
        final value = b.text.text;
        return {
          'type': 'codeBlock',
          if (b.attrs != null) 'attrs': b.attrs,
          if (value.isNotEmpty)
            'content': [
              {'type': 'text', 'text': value},
            ],
        };
      case DocBlockType.rule:
        return {'type': 'horizontalRule'};
      case DocBlockType.opaque:
        return b.raw ?? {'type': 'paragraph'};
      default:
        return _paragraph(b.text);
    }
  }

  static String plainText(List<DocBlock> blocks) {
    final lines = <String>[];
    for (final b in blocks) {
      switch (b.type) {
        case DocBlockType.rule:
        case DocBlockType.opaque:
          break;
        case DocBlockType.heading:
          lines.add('${'#' * b.level.clamp(1, 6).toInt()} ${b.text.text}');
        case DocBlockType.bullet:
          lines.add('${'  ' * b.depth}- ${b.text.text}');
        case DocBlockType.ordered:
          lines.add('${'  ' * b.depth}1. ${b.text.text}');
        case DocBlockType.task:
          lines.add('${'  ' * b.depth}- [${b.checked ? 'x' : ' '}] ${b.text.text}');
        case DocBlockType.quote:
          lines.add('> ${b.text.text}');
        default:
          lines.add(b.text.text);
      }
    }
    return lines.join('\n');
  }
}