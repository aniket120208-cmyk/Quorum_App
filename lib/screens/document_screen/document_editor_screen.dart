import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/document_content.dart';
import 'package:quorum_app/models/document_models.dart';
import 'package:quorum_app/models/whiteboard_models.dart';
import 'package:quorum_app/screens/document_screen/document_controller.dart';
import 'package:quorum_app/screens/document_screen/document_widgets.dart';
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';
import 'package:quorum_app/screens/whiteboard_screen/whiteboard_screen.dart';

class DocumentEditorScreen extends StatefulWidget {
  const DocumentEditorScreen({
    super.key,
    required this.documentId,
    this.initialTitle,
    this.meetingCode,
    this.embedded = false,
    this.headerActions = const [],
  });

  final String documentId;
  final String? initialTitle;
  final String? meetingCode;
  final bool embedded;
  final List<Widget> headerActions;

  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends State<DocumentEditorScreen> {
  late final DocumentController _c = DocumentController(
    documentId: widget.documentId,
    meetingCode: widget.meetingCode,
  );
  final List<DocEntry> _entries = [];
  StreamSubscription<String>? _noticeSub;
  DocEntry? _focused;
  int _seenRevision = 0;
  bool _built = false;
  bool _silent = false;
  EmbeddedWhiteboard? _activeWhiteboard;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
    _noticeSub = _c.notices.listen((message) {
      if (mounted) orgToast(context, message, error: true);
    });
    _c.start();
  }

  @override
  void dispose() {
    _noticeSub?.cancel();
    _c.removeListener(_onController);
    _c.dispose();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  DocEntry _newEntry(DocBlock block) {
    final entry = DocEntry(block);
    entry.ctrl.addListener(() => _onCtrl(entry));
    entry.focus.addListener(() {
      if (entry.focus.hasFocus && !identical(_focused, entry) && mounted) {
        setState(() => _focused = entry);
      }
    });
    return entry;
  }

  void _discard(DocEntry entry) {
    if (identical(_focused, entry)) _focused = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => entry.dispose());
  }

  void _onController() {
    if (!mounted) return;
    if (_c.status == DocumentStatus.ready && !_built) {
      _built = true;
      _entries
        ..clear()
        ..addAll(_c.blocks.map(_newEntry));
      _seenRevision = _c.remoteRevision;
      final boards = _c.doc?.whiteboards ?? const <EmbeddedWhiteboard>[];
      if (boards.isNotEmpty && _activeWhiteboard == null) {
        _activeWhiteboard = boards.first;
      }
    } else if (_c.remoteRevision != _seenRevision) {
      _seenRevision = _c.remoteRevision;
      _reconcile();
    }
    if (_built) _syncCursors();
    setState(() {});
  }

  void _syncCursors() {
    _silent = true;
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final length = entry.ctrl.text.length;
      final selections = [
        for (final c in _c.cursorsOnLine(i))
          if (c.hasSelection)
            RemoteSelection(
              math.min(c.selectionStart!, length),
              math.min(c.selectionEnd!, length),
              documentCursorColor(c.userId),
            ),
      ];
      if (entry.ctrl.setRemoteSelections(selections)) entry.ctrl.refresh();
    }
    _silent = false;
  }

  void _emitCursor(DocEntry entry) {
    final line = _entries.indexOf(entry);
    final sel = entry.ctrl.selection;
    if (line < 0 || !sel.isValid) return;
    _c.sendCursor(
      line,
      sel.extentOffset,
      selectionStart: sel.isCollapsed ? null : sel.start,
      selectionEnd: sel.isCollapsed ? null : sel.end,
    );
  }

  void _reconcile() {
    final remote = _c.blocks;
    _silent = true;
    for (var i = 0; i < remote.length; i++) {
      if (i >= _entries.length) {
        _entries.add(_newEntry(remote[i]));
        continue;
      }
      final entry = _entries[i];
      if (identical(entry.block, remote[i])) continue;
      entry.block = remote[i];
      entry.ctrl.setRich(remote[i].text);
    }
    while (_entries.length > remote.length) {
      _discard(_entries.removeLast());
    }
    _silent = false;
  }

  void _setSilently(DocEntry entry, DocText text) {
    _silent = true;
    entry.block.text = text;
    entry.ctrl.setRich(text);
    _silent = false;
  }

  void _commitStructure() {
    _c.commit(_entries.map((e) => e.block).toList());
    setState(() {});
  }

  void _focusEntry(DocEntry entry, int caret) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_entries.contains(entry)) return;
      entry.focus.requestFocus();
      _silent = true;
      entry.ctrl.selection = TextSelection.collapsed(offset: math.min(caret, entry.ctrl.text.length));
      _silent = false;
      _emitCursor(entry);
    });
  }

  void _onCtrl(DocEntry entry) {
    if (_silent || !mounted || !_entries.contains(entry)) return;
    final block = entry.block;
    final next = entry.ctrl.text;
    if (entry.focus.hasFocus) _emitCursor(entry);
    if (next == block.text.text) {
      if (entry.focus.hasFocus) setState(() {});
      return;
    }
    if (!_c.canEdit) return;
    final ends = commonEnds(block.text.text, next);
    final inserted = next.substring(ends.prefix, next.length - ends.suffix);
    block.text = block.text.edited(next);
    entry.ctrl.rich = block.text;
    if (block.type == DocBlockType.paragraph && block.text.text == '/ai') {
      _setSilently(entry, DocText.empty);
      _c.localChanged();
      _openAi();
      return;
    }
    if (inserted.contains('\n') && block.type != DocBlockType.code) {
      _splitAt(entry, ends.prefix, inserted);
      return;
    }
    _c.localChanged();
  }

  DocBlockType _continuation(DocBlock b) => b.isList ? b.type : DocBlockType.paragraph;

  void _splitAt(DocEntry entry, int start, String inserted) {
    final block = entry.block;
    final full = block.text;
    final positions = <int>[
      for (var i = 0; i < inserted.length; i++)
        if (inserted[i] == '\n') start + i,
    ];
    final pieces = <DocText>[];
    var from = 0;
    for (final p in positions) {
      pieces.add(full.slice(from, p));
      from = p + 1;
    }
    pieces.add(full.slice(from, full.length));
    if (block.isList && positions.length == 1 && pieces[0].isEmpty && pieces[1].isEmpty) {
      _exitList(entry);
      return;
    }
    final tailLength = full.length - (start + inserted.length);
    final index = _entries.indexOf(entry);
    _setSilently(entry, pieces.first);
    final created = [
      for (final piece in pieces.skip(1))
        _newEntry(DocBlock(type: _continuation(block), depth: block.depth, text: piece)),
    ];
    _entries.insertAll(index + 1, created);
    _commitStructure();
    _focusEntry(created.last, math.max(pieces.last.length - tailLength, 0));
  }

  void _exitList(DocEntry entry) {
    final block = entry.block;
    if (block.depth > 0) {
      block.depth -= 1;
    } else {
      block.type = DocBlockType.paragraph;
    }
    _setSilently(entry, DocText.empty);
    _c.localChanged();
    setState(() {});
  }

  void _backspaceAtStart(DocEntry entry) {
    final block = entry.block;
    final index = _entries.indexOf(entry);
    if (index < 0) return;
    if (block.type != DocBlockType.paragraph) {
      if (block.isList && block.depth > 0) {
        block.depth -= 1;
      } else {
        block.type = DocBlockType.paragraph;
        block.depth = 0;
      }
      entry.ctrl.refresh();
      _c.localChanged();
      setState(() {});
      return;
    }
    if (index == 0) return;
    final prev = _entries[index - 1];
    if (!prev.block.isEditable) {
      _entries.removeAt(index - 1);
      _discard(prev);
      _commitStructure();
      return;
    }
    final joinAt = prev.block.text.length;
    final merged = prev.block.text + block.text;
    _entries.removeAt(index);
    _discard(entry);
    _setSilently(prev, merged);
    _commitStructure();
    _focusEntry(prev, joinAt);
  }

  int _numberAt(int index) {
    final depth = _entries[index].block.depth;
    var n = 1;
    for (var j = index - 1; j >= 0; j--) {
      final x = _entries[j].block;
      if (!x.isList || x.depth < depth) break;
      if (x.depth == depth) {
        if (x.type == DocBlockType.ordered) {
          n++;
        } else {
          break;
        }
      }
    }
    return n;
  }

  bool _isActive(String type) {
    final entry = _focused;
    if (entry == null || !_entries.contains(entry)) return false;
    final sel = entry.ctrl.selection;
    if (!sel.isValid) return false;
    final text = entry.block.text;
    if (sel.isCollapsed) {
      return sel.baseOffset > 0 && text.marksAt(sel.baseOffset - 1).any((m) => m['type'] == type);
    }
    return text.allHave(type, sel.start, sel.end);
  }

  TextSelection? _markableSelection() {
    final entry = _focused;
    if (entry == null || !_entries.contains(entry) || !entry.block.isEditable) return null;
    if (entry.block.type == DocBlockType.code) return null;
    final sel = entry.ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) {
      orgToast(context, 'Select some text first');
      return null;
    }
    return sel;
  }

  void _toggleMark(String type) {
    final sel = _markableSelection();
    final entry = _focused;
    if (sel == null || entry == null) return;
    entry.block.text = entry.block.text.toggled(type, sel.start, sel.end);
    entry.ctrl.rich = entry.block.text;
    entry.ctrl.refresh();
    _c.localChanged();
    setState(() {});
  }

  Future<void> _link() async {
    final sel = _markableSelection();
    final entry = _focused;
    if (sel == null || entry == null) return;
    final current = entry.block.text.linkIn(sel.start, sel.end);
    final url = await showOrgSheet<String>(
      context,
      DocumentTextSheet(
        title: current == null ? 'Add link' : 'Edit link',
        hint: 'https://example.com',
        action: 'Apply',
        initial: current ?? '',
        allowEmpty: true,
        maxLength: 500,
        keyboardType: TextInputType.url,
      ),
    );
    if (url == null || !mounted || !_entries.contains(entry)) return;
    final hasScheme = url.contains('://') || url.startsWith('mailto:');
    entry.block.text = url.isEmpty
        ? entry.block.text.withoutMark('link', sel.start, sel.end)
        : entry.block.text.withMark(
            {
              'type': 'link',
              'attrs': {'href': hasScheme ? url : 'https://$url'},
            },
            sel.start,
            sel.end,
          );
    entry.ctrl.rich = entry.block.text;
    entry.ctrl.refresh();
    _c.localChanged();
    setState(() {});
  }

  void _setKind(String key) {
    final entry = _focused;
    if (entry == null || !_entries.contains(entry) || !entry.block.isEditable) return;
    final b = entry.block;
    switch (key) {
      case 'p':
        b.type = DocBlockType.paragraph;
      case 'h1':
        b.type = DocBlockType.heading;
        b.level = 1;
      case 'h2':
        b.type = DocBlockType.heading;
        b.level = 2;
      case 'h3':
        b.type = DocBlockType.heading;
        b.level = 3;
      case 'ul':
        b.type = DocBlockType.bullet;
      case 'ol':
        b.type = DocBlockType.ordered;
      case 'task':
        b.type = DocBlockType.task;
      case 'quote':
        b.type = DocBlockType.quote;
      case 'code':
        b.type = DocBlockType.code;
    }
    if (!b.isList) b.depth = 0;
    entry.ctrl.refresh();
    _c.localChanged();
    setState(() {});
  }

  void _indent() {
    final entry = _focused;
    if (entry == null) return;
    final index = _entries.indexOf(entry);
    final b = entry.block;
    if (!b.isList || index <= 0) return;
    final prev = _entries[index - 1].block;
    if (!prev.isList || b.depth > prev.depth) return;
    b.depth += 1;
    _c.localChanged();
    setState(() {});
  }

  void _outdent() {
    final entry = _focused;
    if (entry == null || !entry.block.isList || entry.block.depth == 0) return;
    entry.block.depth -= 1;
    _c.localChanged();
    setState(() {});
  }

  void _insertDivider() {
    final index = _focused == null ? _entries.length - 1 : _entries.indexOf(_focused!);
    final tail = _newEntry(DocBlock(type: DocBlockType.paragraph));
    _entries.insertAll(index + 1, [_newEntry(DocBlock(type: DocBlockType.rule)), tail]);
    _commitStructure();
    _focusEntry(tail, 0);
  }

  void _deleteBlock([DocEntry? target]) {
    final entry = target ?? _focused;
    if (entry == null) return;
    final index = _entries.indexOf(entry);
    if (index < 0) return;
    _entries.removeAt(index);
    _discard(entry);
    if (_entries.isEmpty) _entries.add(_newEntry(DocBlock(type: DocBlockType.paragraph)));
    _commitStructure();
    final next = _entries[math.min(index, _entries.length - 1)];
    if (next.block.isEditable) _focusEntry(next, 0);
  }

  void _tapEnd() {
    if (!_c.canEdit) return;
    final last = _entries.isEmpty ? null : _entries.last;
    if (last != null && last.block.type == DocBlockType.paragraph && last.block.text.isEmpty) {
      _focusEntry(last, 0);
      return;
    }
    final entry = _newEntry(DocBlock(type: DocBlockType.paragraph));
    _entries.add(entry);
    _commitStructure();
    _focusEntry(entry, 0);
  }

  void _replaceSelection(DocEntry entry, TextSelection sel, String text) {
    final replacement = markdownInline(text.trim());
    final full = entry.block.text;
    final next = full.slice(0, sel.start) + replacement + full.slice(sel.end, full.length);
    _setSilently(entry, next);
    _c.localChanged();
    setState(() {});
  }

  Future<void> _openAi() async {
    if (!_c.canEdit) return;
    final entry = _focused;
    TextSelection? sel;
    var selected = '';
    if (entry != null && _entries.contains(entry) && entry.block.isEditable) {
      final s = entry.ctrl.selection;
      if (s.isValid && !s.isCollapsed && s.end <= entry.ctrl.text.length) {
        sel = s;
        selected = entry.ctrl.text.substring(s.start, s.end);
      }
    }
    final result = await showOrgSheet<DocumentAiResult>(
      context,
      DocumentAiSheet(
        documentId: widget.documentId,
        contextText: DocContent.plainText(_entries.map((e) => e.block).toList()),
        selectedText: selected,
        canReplaceSelection: sel != null,
        initialAction: widget.meetingCode != null ? DocumentAiAction.actionItems : DocumentAiAction.summarize,
      ),
    );
    if (result == null || !mounted) return;
    if (result.replaceSelection && sel != null && entry != null && _entries.contains(entry)) {
      _replaceSelection(entry, sel, result.text);
      return;
    }
    final blocks = markdownToBlocks(result.text);
    if (blocks.isEmpty) return;
    final focused = _focused;
    var index = focused != null && _entries.contains(focused) ? _entries.indexOf(focused) + 1 : _entries.length;
    if (focused != null && index > 0) {
      final prev = _entries[index - 1];
      if (identical(prev, focused) && prev.block.type == DocBlockType.paragraph && prev.block.text.isEmpty) {
        _entries.removeAt(index - 1);
        _discard(prev);
        index -= 1;
      }
    }
    _entries.insertAll(index, blocks.map(_newEntry));
    _commitStructure();
  }

  Future<void> _openActiveWhiteboard() async {
    final current = _activeWhiteboard;
    if (current == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WhiteboardScreen(
          boardId: current.whiteboardId,
          name: current.name,
          meetingCode: widget.meetingCode,
        ),
      ),
    );
  }

  Future<void> _selectWhiteboardFromNav() async {
    final docBoards = _c.doc?.whiteboards ?? const <EmbeddedWhiteboard>[];
    final selected = await showModalBottomSheet<dynamic>(
      context: context,
      backgroundColor: orgBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Whiteboards',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (_c.canEdit)
                      TextButton.icon(
                        icon: const Icon(Icons.add, color: orgTeal, size: 20),
                        label: const Text('Add', style: TextStyle(color: orgTeal)),
                        onPressed: () => Navigator.pop(context, 'add_new'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (docBoards.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        'No whiteboards linked to this document.',
                        style: TextStyle(color: orgMuted),
                      ),
                    ),
                  ),
                for (final board in docBoards)
                  ListTile(
                    leading: const Icon(Icons.draw_outlined, color: orgTeal),
                    title: Text(board.name, style: const TextStyle(color: Colors.white)),
                    trailing: _activeWhiteboard?.whiteboardId == board.whiteboardId
                        ? const Icon(Icons.check_rounded, color: orgTeal)
                        : null,
                    onTap: () => Navigator.pop(context, board),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    if (selected == 'add_new') {
      final board = await showOrgSheet<Whiteboard>(
        context,
        DocumentWhiteboardPickerSheet(
          meetingCode: widget.meetingCode,
          organizationId: _c.doc?.organizationId,
        ),
      );
      if (board == null || !mounted) return;
      _c.embedWhiteboard(board.id, board.name);
      final updated = _c.doc?.whiteboards ?? const <EmbeddedWhiteboard>[];
      setState(() {
        _activeWhiteboard = updated.isNotEmpty
            ? (updated.any((b) => b.whiteboardId == board.id)
                ? updated.firstWhere((b) => b.whiteboardId == board.id)
                : updated.last)
            : null;
      });
      return;
    }

    if (selected is EmbeddedWhiteboard) {
      setState(() {
        _activeWhiteboard = selected;
      });
    }
  }

  Future<void> _rename() async {
    final doc = _c.doc;
    if (doc == null || !_c.canEdit) return;
    final title = await showOrgSheet<String>(
      context,
      DocumentTextSheet(title: 'Rename document', hint: 'Document title', action: 'Save', initial: doc.title),
    );
    if (title == null || title == doc.title || !mounted) return;
    try {
      await _c.rename(title);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  Widget _readyBody(bool editable) {
    final boards = _c.doc?.whiteboards ?? const <EmbeddedWhiteboard>[];
    if (_activeWhiteboard == null && boards.isNotEmpty) {
      _activeWhiteboard = boards.first;
    }

    return Stack(
      children: [
        Column(
          children: [
            if (_c.offline)
              Container(
                width: double.infinity,
                color: const Color(0xFF2A2415),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  'Offline, your changes will sync when you reconnect',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _entries.length + 1,
                itemBuilder: (context, i) {
                  if (i < _entries.length) {
                    final entry = _entries[i];
                    return DocBlockRow(
                      key: ObjectKey(entry),
                      entry: entry,
                      number: entry.block.type == DocBlockType.ordered ? _numberAt(i) : 0,
                      isFirst: i == 0,
                      editable: editable,
                      cursors: _c.cursorsOnLine(i),
                      onToggleChecked: () {
                        entry.block.checked = !entry.block.checked;
                        _c.localChanged();
                        setState(() {});
                      },
                      onBackspaceAtStart: () => _backspaceAtStart(entry),
                      onDelete: () => _deleteBlock(entry),
                    );
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _tapEnd,
                    child: const SizedBox(height: 160),
                  );
                },
              ),
            ),
            if (editable)
              DocToolbar(
                enabled: _focused != null && _entries.contains(_focused) && _focused!.block.isEditable,
                isActive: _isActive,
                onMark: _toggleMark,
                onLink: _link,
                onKind: _setKind,
                onIndent: _indent,
                onOutdent: _outdent,
                onDivider: _insertDivider,
                onDeleteBlock: _deleteBlock,
              ),
          ],
        ),
        if (_activeWhiteboard != null)
          Positioned(
            right: 0,
            top: MediaQuery.of(context).size.height * 0.35,
            child: Material(
              color: orgCard,
              elevation: 4,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                onTap: _openActiveWhiteboard,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                    border: Border.all(color: orgBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chevron_left_rounded, color: orgMuted, size: 18),
                      SizedBox(width: 2),
                      Icon(Icons.draw_outlined, color: orgTeal, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _body(bool editable) {
    switch (_c.status) {
      case DocumentStatus.loading:
        return const Center(child: CircularProgressIndicator(color: orgTeal));
      case DocumentStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: orgMuted, size: 40),
                const SizedBox(height: 12),
                Text(_c.error ?? 'Could not open this document.',
                    textAlign: TextAlign.center, style: const TextStyle(color: orgMuted)),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _c.retry,
                  child: const Text('Try again', style: TextStyle(color: orgTeal, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      case DocumentStatus.ready:
        return _readyBody(editable);
    }
  }

  List<Widget> _actions({required bool ready, required bool editable, required QuorumDoc? doc, bool compact = false}) {
    return [
      if (ready && !_c.canEdit) const DocumentViewOnlyPill(),
      DocumentPresenceBar(users: _c.otherUsers),
      IconButton(
        tooltip: 'Switch whiteboard',
        icon: const Icon(Icons.draw_outlined, color: orgTeal),
        onPressed: _selectWhiteboardFromNav,
      ),
      if (editable)
        IconButton(
          tooltip: 'Ask AI',
          icon: const Icon(Icons.auto_awesome_rounded, color: orgTeal),
          onPressed: _openAi,
        ),
      if (doc != null)
        IconButton(
          tooltip: 'People',
          icon: const Icon(Icons.people_alt_outlined),
          onPressed: () => showDocumentInfoSheet(context, doc),
        ),
    ];
  }

  Widget _embeddedShell(QuorumDoc? doc, bool ready, bool editable) {
    return Material(
      color: orgBg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: orgBorder))),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: editable ? _rename : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          doc?.title ?? widget.initialTitle ?? 'Document',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _c.offline ? const Color(0xFFF59E0B) : Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _c.offline ? 'Offline' : 'Collaborating live',
                              style: const TextStyle(color: orgMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Theme(
                  data: Theme.of(context).copyWith(
                    iconButtonTheme: IconButtonThemeData(
                      style: IconButton.styleFrom(foregroundColor: Colors.white),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ..._actions(ready: ready, editable: editable, doc: doc, compact: true),
                      ...widget.headerActions,
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body(editable)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _c.doc;
    final ready = _c.status == DocumentStatus.ready;
    final editable = ready && _c.canEdit;
    if (widget.embedded) return _embeddedShell(doc, ready, editable);
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: editable ? _rename : null,
          child: Text(
            doc?.title ?? widget.initialTitle ?? 'Document',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        actions: _actions(ready: ready, editable: editable, doc: doc),
      ),
      body: _body(editable),
    );
  }
}