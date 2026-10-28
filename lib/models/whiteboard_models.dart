import 'dart:convert';
import 'dart:ui';

Map<String, dynamic> _asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String? _str(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty || s == 'null') return null;
  return s;
}

DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();

double _num(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? fallback;
}

double _round(double v) => (v * 10).roundToDouble() / 10;

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

String colorToHex(Color c) => '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

List<dynamic> _listFrom(dynamic d, List<String> keys) {
  if (d is List) return d;
  if (d is Map) {
    for (final k in keys) {
      if (d[k] is List) return d[k] as List;
    }
  }
  return const [];
}

class WhiteboardElement {
  WhiteboardElement(Map<String, dynamic> source) : json = Map<String, dynamic>.from(source);
  final Map<String, dynamic> json;

  String get id => (json['id'] ?? '').toString();
  String get type => (json['type'] ?? '').toString();
  double get x => _num(json['x']);
  double get y => _num(json['y']);
  String get text => (json['text'] ?? '').toString();
  double get fontSize => _num(json['fontSize'], 18);
  double get strokeWidth => _num(json['strokeWidth'], 3);
  Color get strokeColor => parseHexColor(_str(json['strokeColor'])) ?? const Color(0xFF0F172A);
  Color get textColor => parseHexColor(_str(json['color'])) ?? const Color(0xFF0F172A);

  late final List<Offset> points = _parsePoints();

  List<Offset> _parsePoints() {
    final raw = json['points'];
    if (raw is! List) return const [];
    final out = <Offset>[];
    for (final p in raw) {
      if (p is List && p.length >= 2) {
        out.add(Offset(_num(p[0]), _num(p[1])));
      } else if (p is Map) {
        out.add(Offset(_num(p['x']), _num(p['y'])));
      }
    }
    return out;
  }

  WhiteboardElement translated(double dx, double dy) {
    final next = Map<String, dynamic>.from(json);
    if (type == 'stroke') {
      next['points'] = points.map((p) => [_round(p.dx + dx), _round(p.dy + dy)]).toList();
    } else if (json.containsKey('x') && json.containsKey('y')) {
      next['x'] = _round(x + dx);
      next['y'] = _round(y + dy);
    }
    return WhiteboardElement(next);
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(json);

  static WhiteboardElement? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final el = WhiteboardElement(Map<String, dynamic>.from(raw));
    if (el.id.isEmpty || el.type.isEmpty) return null;
    return el;
  }

  static List<WhiteboardElement> parseList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map(tryParse).whereType<WhiteboardElement>().toList();
  }

  static double round(double v) => _round(v);
}

class WhiteboardViewState {
  const WhiteboardViewState({
    this.zoom = 1,
    this.scrollX = 0,
    this.scrollY = 0,
    this.backgroundColor = '#ffffff',
  });

  final double zoom;
  final double scrollX;
  final double scrollY;
  final String backgroundColor;

  WhiteboardViewState copyWith({double? zoom, double? scrollX, double? scrollY, String? backgroundColor}) {
    return WhiteboardViewState(
      zoom: zoom ?? this.zoom,
      scrollX: scrollX ?? this.scrollX,
      scrollY: scrollY ?? this.scrollY,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  factory WhiteboardViewState.fromJson(dynamic raw) {
    final j = _asMap(raw);
    final zoom = _num(j['zoom'], 1);
    return WhiteboardViewState(
      zoom: zoom <= 0 ? 1 : zoom,
      scrollX: _num(j['scrollX']),
      scrollY: _num(j['scrollY']),
      backgroundColor: _str(j['backgroundColor']) ?? '#ffffff',
    );
  }

  Map<String, dynamic> toJson() => {
        'zoom': zoom,
        'scrollX': scrollX,
        'scrollY': scrollY,
        'backgroundColor': backgroundColor,
      };
}

class Whiteboard {
  const Whiteboard({
    required this.id,
    required this.name,
    this.organizationId,
    this.createdAt,
    this.updatedAt,
    this.elements = const [],
    this.viewState = const WhiteboardViewState(),
  });

  final String id;
  final String name;
  final String? organizationId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<WhiteboardElement> elements;
  final WhiteboardViewState viewState;

  Whiteboard copyWith({String? name}) => Whiteboard(
        id: id,
        name: name ?? this.name,
        organizationId: organizationId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        elements: elements,
        viewState: viewState,
      );

  factory Whiteboard.fromJson(dynamic raw) {
    var j = _asMap(raw);
    if (j['whiteboard'] is Map) j = _asMap(j['whiteboard']);
    dynamic content = j['content'];
    if (content is String) {
      try {
        content = jsonDecode(content);
      } catch (_) {
        content = null;
      }
    }
    final c = _asMap(content);
    return Whiteboard(
      id: (j['id'] ?? j['_id'] ?? j['whiteboardId'] ?? '').toString(),
      name: _str(j['name']) ?? _str(j['title']) ?? 'Untitled board',
      organizationId: _str(j['organizationId']),
      createdAt: _date(j['createdAt']),
      updatedAt: _date(j['updatedAt']),
      elements: WhiteboardElement.parseList(c['elements']),
      viewState: WhiteboardViewState.fromJson(c['viewState']),
    );
  }
}

class WhiteboardPage {
  const WhiteboardPage({required this.items, required this.page, required this.hasMore});

  final List<Whiteboard> items;
  final int page;
  final bool hasMore;

  factory WhiteboardPage.fromJson(dynamic raw, {required int page, required int limit}) {
    final items = _listFrom(raw, const ['whiteboards', 'items', 'boards', 'data'])
        .map(Whiteboard.fromJson)
        .where((b) => b.id.isNotEmpty)
        .toList();
    final meta = raw is Map ? _asMap(raw['pagination'] ?? raw['meta']) : <String, dynamic>{};
    final totalPages = int.tryParse('${meta['totalPages'] ?? meta['pages'] ?? ''}');
    final total = int.tryParse('${meta['total'] ?? meta['totalCount'] ?? ''}');
    bool hasMore;
    if (totalPages != null) {
      hasMore = page < totalPages;
    } else if (total != null) {
      hasMore = page * limit < total;
    } else {
      hasMore = items.length >= limit;
    }
    return WhiteboardPage(items: items, page: page, hasMore: hasMore);
  }
}

class OpenedWhiteboard {
  const OpenedWhiteboard({required this.whiteboard, this.socketRoom});
  final Whiteboard whiteboard;
  final String? socketRoom;

  factory OpenedWhiteboard.fromJson(dynamic raw) {
    final j = _asMap(raw);
    return OpenedWhiteboard(
      whiteboard: Whiteboard.fromJson(j['whiteboard'] ?? j),
      socketRoom: _str(j['socketRoom']),
    );
  }
}

class WhiteboardPresence {
  const WhiteboardPresence({required this.key, required this.name, this.userId, this.socketId});

  final String key;
  final String name;
  final String? userId;
  final String? socketId;

  static WhiteboardPresence? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final user = j['user'] is Map ? Map<String, dynamic>.from(j['user']) : j;
    final userId = _str(user['userId'] ?? user['id']);
    final socketId = _str(j['socketId'] ?? user['socketId']);
    final key = userId ?? socketId;
    if (key == null) return null;
    return WhiteboardPresence(
      key: key,
      name: _str(user['name'] ?? user['username']) ?? 'Guest',
      userId: userId,
      socketId: socketId,
    );
  }
}

class RemoteCursor {
  RemoteCursor({required this.key, required this.name, required this.x, required this.y, required this.updatedAt});
  final String key;
  final String name;
  final double x;
  final double y;
  final DateTime updatedAt;
}

Map<String, dynamic> emptyWhiteboardContent() => {
      'elements': <Map<String, dynamic>>[],
      'viewState': const WhiteboardViewState().toJson(),
    };