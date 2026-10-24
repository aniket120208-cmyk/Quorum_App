import 'package:flutter/material.dart';

enum SavedItemType {
  message('MESSAGE', 'Messages'),
  file('FILE', 'Files'),
  chat('CHAT', 'Chats'),
  document('DOCUMENT', 'Documents'),
  resource('RESOURCE', 'Resources');

  const SavedItemType(this.value, this.label);
  final String value;
  final String label;

  static SavedItemType from(String? raw) {
    for (final t in SavedItemType.values) {
      if (t.value == raw?.toUpperCase()) return t;
    }
    return SavedItemType.resource;
  }
}

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String toHexColor(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0')}';
}

DateTime? _date(dynamic v) => DateTime.tryParse((v ?? '').toString())?.toLocal();

class SavedCollectionRef {
  final String id;
  final String name;
  final String? color;
  const SavedCollectionRef({required this.id, required this.name, this.color});

  factory SavedCollectionRef.fromJson(Map<String, dynamic> j) => SavedCollectionRef(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        color: j['color']?.toString(),
      );
}

class SavedCollection {
  final String id;
  final String name;
  final String? description;
  final String? color;
  final int itemCount;

  const SavedCollection({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.itemCount = 0,
  });

  factory SavedCollection.fromJson(Map<String, dynamic> j) {
    final counts = j['_count'] is Map ? Map<String, dynamic>.from(j['_count']) : <String, dynamic>{};
    return SavedCollection(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      description: j['description']?.toString(),
      color: j['color']?.toString(),
      itemCount: int.tryParse((counts['items'] ?? 0).toString()) ?? 0,
    );
  }
}

class SavedItem {
  final String id;
  final SavedItemType type;
  final String itemId;
  final String? note;
  final bool isAccessible;
  final String title;
  final Map<String, dynamic>? content;
  final SavedCollectionRef? collection;
  final DateTime? createdAt;

  const SavedItem({
    required this.id,
    required this.type,
    required this.itemId,
    this.note,
    this.isAccessible = true,
    this.title = '',
    this.content,
    this.collection,
    this.createdAt,
  });

  SavedItem copyWith({
    String? note,
    bool clearNote = false,
    SavedCollectionRef? collection,
    bool clearCollection = false,
  }) =>
      SavedItem(
        id: id,
        type: type,
        itemId: itemId,
        note: clearNote ? null : (note ?? this.note),
        isAccessible: isAccessible,
        title: title,
        content: content,
        collection: clearCollection ? null : (collection ?? this.collection),
        createdAt: createdAt,
      );

  factory SavedItem.fromJson(Map<String, dynamic> j) {
    final note = j['note']?.toString();
    return SavedItem(
      id: (j['id'] ?? '').toString(),
      type: SavedItemType.from(j['itemType']?.toString()),
      itemId: (j['itemId'] ?? '').toString(),
      note: (note == null || note.isEmpty) ? null : note,
      isAccessible: j['isAccessible'] != false,
      title: (j['title'] ?? '').toString(),
      content: j['content'] is Map ? Map<String, dynamic>.from(j['content']) : null,
      collection: j['collection'] is Map
          ? SavedCollectionRef.fromJson(Map<String, dynamic>.from(j['collection']))
          : null,
      createdAt: _date(j['createdAt']),
    );
  }
}