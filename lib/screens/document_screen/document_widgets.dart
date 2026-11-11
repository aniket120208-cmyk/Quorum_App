import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/document_repository.dart';
import 'package:quorum_app/api/whiteboard_repository.dart';
import 'package:quorum_app/models/whiteboard_models.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/models/document_content.dart';
import 'package:quorum_app/models/document_models.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart' show ChatAvatar;
import 'package:quorum_app/screens/organization_screen/organization_sheets.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

String documentAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Updated just now';
  if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
  if (diff.inDays < 30) return 'Updated ${diff.inDays}d ago';
  return 'Updated ${time.day}/${time.month}/${time.year}';
}

TextStyle docMarkStyle(List<DocMark> marks) {
  FontWeight? weight;
  FontStyle? fontStyle;
  String? family;
  Color? background;
  Color? color;
  final decorations = <TextDecoration>[];
  for (final m in marks) {
    switch (m['type']) {
      case 'bold':
        weight = FontWeight.w700;
      case 'italic':
        fontStyle = FontStyle.italic;
      case 'underline':
        decorations.add(TextDecoration.underline);
      case 'strike':
        decorations.add(TextDecoration.lineThrough);
      case 'code':
        family = 'monospace';
        background = const Color(0x33FFFFFF);
      case 'highlight':
        background = const Color(0x66F59E0B);
      case 'link':
        color = orgTeal;
        decorations.add(TextDecoration.underline);
    }
  }
  return TextStyle(
    fontWeight: weight,
    fontStyle: fontStyle,
    fontFamily: family,
    backgroundColor: background,
    color: color,
    decoration: decorations.isEmpty ? null : TextDecoration.combine(decorations),
  );
}

TextStyle docBlockStyle(DocBlock b) {
  switch (b.type) {
    case DocBlockType.heading:
      final size = switch (b.level) {
        1 => 28.0,
        2 => 22.0,
        3 => 18.0,
        _ => 16.0,
      };
      return TextStyle(color: Colors.white, fontSize: size, fontWeight: FontWeight.w700, height: 1.3);
    case DocBlockType.code:
      return const TextStyle(color: orgTeal, fontSize: 13.5, fontFamily: 'monospace', height: 1.5);
    case DocBlockType.quote:
      return const TextStyle(color: Color(0xFFD1D5DB), fontSize: 16, fontStyle: FontStyle.italic, height: 1.5);
    case DocBlockType.task:
      return TextStyle(
        color: b.checked ? orgMuted : Colors.white,
        fontSize: 16,
        height: 1.5,
        decoration: b.checked ? TextDecoration.lineThrough : null,
      );
    default:
      return const TextStyle(color: Colors.white, fontSize: 16, height: 1.5);
  }
}

String? docBlockHint(DocBlock b, {required bool first}) {
  switch (b.type) {
    case DocBlockType.heading:
      return 'Heading';
    case DocBlockType.bullet:
    case DocBlockType.ordered:
    case DocBlockType.task:
      return 'List item';
    case DocBlockType.quote:
      return 'Quote';
    case DocBlockType.code:
      return 'Code';
    default:
      return first ? "Write something, or type '/ai'" : null;
  }
}

const List<Color> documentCursorColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

Color documentCursorColor(String userId) {
  var sum = 0;
  for (final unit in userId.codeUnits) {
    sum += unit;
  }
  return documentCursorColors[sum % documentCursorColors.length];
}

class RemoteSelection {
  const RemoteSelection(this.start, this.end, this.color);
  final int start;
  final int end;
  final Color color;

  @override
  bool operator ==(Object other) => other is RemoteSelection && other.start == start && other.end == end && other.color == color;

  @override
  int get hashCode => Object.hash(start, end, color);
}

class RichTextController extends TextEditingController {
  RichTextController(this.rich) : super(text: rich.text);
  DocText rich;
  List<RemoteSelection> remoteSelections = const [];

  bool setRemoteSelections(List<RemoteSelection> next) {
    if (next.length == remoteSelections.length) {
      var same = true;
      for (var i = 0; i < next.length; i++) {
        if (next[i] != remoteSelections[i]) {
          same = false;
          break;
        }
      }
      if (same) return false;
    }
    remoteSelections = next;
    return true;
  }

  List<InlineSpan> _runSpans() {
    final out = <InlineSpan>[];
    var pos = 0;
    for (final r in rich.runs) {
      final base = docMarkStyle(r.marks);
      final runStart = pos;
      final runEnd = pos + r.text.length;
      pos = runEnd;
      if (r.text.isEmpty) continue;
      final cuts = <int>{runStart, runEnd};
      for (final sel in remoteSelections) {
        if (sel.start > runStart && sel.start < runEnd) cuts.add(sel.start);
        if (sel.end > runStart && sel.end < runEnd) cuts.add(sel.end);
      }
      final sorted = cuts.toList()..sort();
      for (var i = 0; i < sorted.length - 1; i++) {
        final a = sorted[i];
        final b = sorted[i + 1];
        Color? tint;
        for (final sel in remoteSelections) {
          if (a >= sel.start && b <= sel.end) tint = sel.color.withAlpha(96);
        }
        out.add(TextSpan(
          text: r.text.substring(a - runStart, b - runStart),
          style: tint == null ? base : base.copyWith(backgroundColor: tint),
        ));
      }
    }
    return out;
  }

  void setRich(DocText next) {
    rich = next;
    final raw = selection.isValid ? selection.baseOffset : 0;
    final offset = math.min(math.max(raw, 0), next.length);
    value = TextEditingValue(text: next.text, selection: TextSelection.collapsed(offset: offset));
  }
  void refresh() => notifyListeners();

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    if (rich.text != text) return TextSpan(style: style, text: text);
    return TextSpan(style: style, children: _runSpans());
  }
}

class DocEntry {
  DocEntry(this.block) : ctrl = RichTextController(block.text), focus = FocusNode();
  DocBlock block;
  final RichTextController ctrl;
  final FocusNode focus;

  void dispose() {
    ctrl.dispose();
    focus.dispose();
  }
}

class DocBlockRow extends StatelessWidget {
  const DocBlockRow({
    super.key,
    required this.entry,
    required this.number,
    required this.isFirst,
    required this.editable,
    required this.onToggleChecked,
    required this.onBackspaceAtStart,
    required this.onDelete,
    this.cursors = const [],
  });

  final DocEntry entry;
  final int number;
  final bool isFirst;
  final bool editable;
  final List<DocumentCursor> cursors;
  final VoidCallback onToggleChecked;
  final VoidCallback onBackspaceAtStart;
  final VoidCallback onDelete;

  Widget _field() {
    final b = entry.block;
    final style = docBlockStyle(b);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
          final sel = entry.ctrl.selection;
          if (editable && sel.isValid && sel.isCollapsed && sel.baseOffset == 0) {
            onBackspaceAtStart();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: entry.ctrl,
        focusNode: entry.focus,
        readOnly: !editable,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: b.type == DocBlockType.code ? TextCapitalization.none : TextCapitalization.sentences,
        autocorrect: b.type != DocBlockType.code,
        enableSuggestions: b.type != DocBlockType.code,
        cursorColor: orgTeal,
        style: style,
        decoration: InputDecoration.collapsed(
          hintText: editable ? docBlockHint(b, first: isFirst) : null,
          hintStyle: style.copyWith(color: const Color(0xFF5B6070), fontStyle: FontStyle.normal),
        ),
      ),
    );
  }

  Widget _leading(DocBlock b) {
    switch (b.type) {
      case DocBlockType.bullet:
        return SizedBox(
          width: 22,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(b.depth.isEven ? '•' : '◦', style: const TextStyle(color: orgMuted, fontSize: 20, height: 1.3)),
          ),
        );
      case DocBlockType.ordered:
        return SizedBox(
          width: 28,
          child: Text('$number.', style: const TextStyle(color: orgMuted, fontSize: 16, height: 1.5)),
        );
      case DocBlockType.task:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: editable ? onToggleChecked : null,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: Icon(
              b.checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 22,
              color: b.checked ? orgTeal : orgMuted,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = entry.block;
    if (b.type == DocBlockType.rule) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Expanded(child: Divider(color: orgBorder, thickness: 1.5, height: 1.5)),
            if (editable)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: orgMuted),
                onPressed: onDelete,
              ),
          ],
        ),
      );
    }
    if (b.type == DocBlockType.opaque) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.extension_outlined, size: 20, color: orgMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${b.rawType} block, view and edit it on the web',
                style: const TextStyle(color: orgMuted, fontSize: 13),
              ),
            ),
            if (editable)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: orgMuted),
                onPressed: onDelete,
              ),
          ],
        ),
      );
    }

    Widget body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_leading(b), Expanded(child: _field())],
    );

    if (b.type == DocBlockType.quote) {
      body = Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: orgTeal, width: 3))),
        child: _field(),
      );
    } else if (b.type == DocBlockType.code) {
      body = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: orgField, borderRadius: BorderRadius.circular(10)),
        child: _field(),
      );
    }

    final padded = Padding(
      padding: EdgeInsets.only(
        left: b.isList ? b.depth * 22.0 : 0,
        top: b.type == DocBlockType.heading ? 14 : 3,
        bottom: 3,
      ),
      child: body,
    );
    if (cursors.isEmpty) return padded;
    final lead = cursors.first;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: documentCursorColor(lead.userId), width: 2)),
      ),
      padding: const EdgeInsets.only(left: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [for (final c in cursors) DocumentCursorFlag(cursor: c)],
          ),
          padded,
        ],
      ),
    );
  }
}

class DocumentCursorFlag extends StatelessWidget {
  const DocumentCursorFlag({super.key, required this.cursor});

  final DocumentCursor cursor;

  @override
  Widget build(BuildContext context) {
    final name = cursor.name.isEmpty ? 'Someone' : cursor.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: documentCursorColor(cursor.userId),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        cursor.hasSelection ? '$name • selecting' : name,
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class DocToolbar extends StatelessWidget {
  const DocToolbar({
    super.key,
    required this.enabled,
    required this.isActive,
    required this.onMark,
    required this.onLink,
    required this.onKind,
    required this.onIndent,
    required this.onOutdent,
    required this.onDivider,
    required this.onDeleteBlock,
  });

  final bool enabled;
  final bool Function(String markType) isActive;
  final ValueChanged<String> onMark;
  final VoidCallback onLink;
  final ValueChanged<String> onKind;
  final VoidCallback onIndent;
  final VoidCallback onOutdent;
  final VoidCallback onDivider;
  final VoidCallback onDeleteBlock;

  Widget _button(IconData icon, VoidCallback onTap, {bool active = false, String? tooltip}) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onTap : null,
      style: IconButton.styleFrom(backgroundColor: active ? const Color(0xFF16302F) : null),
      icon: Icon(icon, size: 22, color: !enabled ? const Color(0xFF4B5060) : (active ? orgTeal : Colors.white)),
    );
  }

  Widget _gap() => const SizedBox(height: 22, child: VerticalDivider(width: 14, color: orgBorder));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: orgCard, border: Border(top: BorderSide(color: orgBorder))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _button(Icons.format_bold_rounded, () => onMark('bold'), active: isActive('bold'), tooltip: 'Bold'),
              _button(Icons.format_italic_rounded, () => onMark('italic'), active: isActive('italic'), tooltip: 'Italic'),
              _button(Icons.format_underlined_rounded, () => onMark('underline'),
                  active: isActive('underline'), tooltip: 'Underline'),
              _button(Icons.format_strikethrough_rounded, () => onMark('strike'),
                  active: isActive('strike'), tooltip: 'Strikethrough'),
              _button(Icons.code_rounded, () => onMark('code'), active: isActive('code'), tooltip: 'Inline code'),
              _button(Icons.link_rounded, onLink, active: isActive('link'), tooltip: 'Link'),
              _gap(),
              PopupMenuButton<String>(
                enabled: enabled,
                color: orgCard,
                tooltip: 'Block type',
                icon: Icon(Icons.text_fields_rounded,
                    size: 22, color: enabled ? Colors.white : const Color(0xFF4B5060)),
                onSelected: onKind,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'p', child: Text('Paragraph', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'h1', child: Text('Heading 1', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'h2', child: Text('Heading 2', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'h3', child: Text('Heading 3', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'ul', child: Text('Bullet list', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'ol', child: Text('Numbered list', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'task', child: Text('Task list', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'quote', child: Text('Quote', style: TextStyle(color: Colors.white))),
                  PopupMenuItem(value: 'code', child: Text('Code block', style: TextStyle(color: Colors.white))),
                ],
              ),
              _button(Icons.format_indent_decrease_rounded, onOutdent, tooltip: 'Outdent'),
              _button(Icons.format_indent_increase_rounded, onIndent, tooltip: 'Indent'),
              _gap(),
              _button(Icons.horizontal_rule_rounded, onDivider, tooltip: 'Divider'),
              _button(Icons.delete_outline_rounded, onDeleteBlock, tooltip: 'Delete block'),
            ],
          ),
        ),
      ),
    );
  }
}

class DocumentTextSheet extends StatefulWidget {
  const DocumentTextSheet({
    super.key,
    required this.title,
    required this.hint,
    required this.action,
    this.initial = '',
    this.allowEmpty = false,
    this.maxLength = 120,
    this.keyboardType = TextInputType.text,
  });

  final String title;
  final String hint;
  final String action;
  final String initial;
  final bool allowEmpty;
  final int maxLength;
  final TextInputType keyboardType;

  @override
  State<DocumentTextSheet> createState() => _DocumentTextSheetState();
}

class _DocumentTextSheetState extends State<DocumentTextSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    if (value.isEmpty && !widget.allowEmpty) {
      setState(() => _error = 'This field is required');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboardType,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(color: orgMuted),
              errorText: _error,
              counterText: '',
              filled: true,
              fillColor: orgField,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: orgAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(widget.action, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class DocumentPresenceBar extends StatelessWidget {
  const DocumentPresenceBar({super.key, required this.users});

  final List<ActiveDocumentUser> users;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return const SizedBox.shrink();
    final shown = users.take(3).toList();
    final extra = users.length - shown.length;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final u in shown)
            Tooltip(
              message: u.name,
              child: Container(
                margin: const EdgeInsets.only(left: 2),
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(color: orgTeal, shape: BoxShape.circle),
                child: ChatAvatar(name: u.name, imageUrl: u.avatar, radius: 12),
              ),
            ),
          if (extra > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('+$extra', style: const TextStyle(color: orgMuted, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class DocumentViewOnlyPill extends StatelessWidget {
  const DocumentViewOnlyPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2415),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5A4A1A)),
      ),
      child: const Text(
        'View Only',
        style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _accessLabel(DocumentAccess a) {
  switch (a) {
    case DocumentAccess.owner:
      return 'Owner';
    case DocumentAccess.write:
      return 'Can edit';
    case DocumentAccess.read:
      return 'View only';
  }
}

Future<void> showDocumentInfoSheet(BuildContext context, QuorumDoc doc) {
  return showOrgSheet<void>(
    context,
    ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        children: [
          Text(doc.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${doc.scopeType.label} document • version ${doc.version}',
            style: const TextStyle(color: orgMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 18),
          const Text('People with access', style: TextStyle(color: orgMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _personRow(doc.createdBy.name, doc.createdBy.email, doc.createdBy.avatar, 'Owner'),
          for (final c in doc.collaborators)
            _personRow(c.user.name, c.user.email, c.user.avatar, _accessLabel(c.permission)),
        ],
      ),
    ),
  );
}

Widget _personRow(String name, String? email, String? avatar, String role) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        ChatAvatar(name: name, imageUrl: avatar, radius: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Unknown' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              if (email != null && email.isNotEmpty)
                Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: orgMuted, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: orgField, borderRadius: BorderRadius.circular(20)),
          child: Text(role, style: const TextStyle(color: orgTeal, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class DocumentAiSheet extends StatefulWidget {
  const DocumentAiSheet({
    super.key,
    required this.documentId,
    required this.contextText,
    this.selectedText = '',
    this.canReplaceSelection = false,
    this.initialAction = DocumentAiAction.summarize,
  });

  final String documentId;
  final String contextText;
  final String selectedText;
  final bool canReplaceSelection;
  final DocumentAiAction initialAction;

  @override
  State<DocumentAiSheet> createState() => _DocumentAiSheetState();
}

class _DocumentAiSheetState extends State<DocumentAiSheet> {
  final TextEditingController _prompt = TextEditingController();
  late DocumentAiAction _action = widget.initialAction;
  bool _loading = false;
  String? _answer;
  DocumentAiAction? _answered;
  String? _error;

  bool get _hasSelection => widget.selectedText.trim().isNotEmpty;

  String get _source {
    final text = _hasSelection ? widget.selectedText : widget.contextText;
    return text.length > 6000 ? text.substring(0, 6000) : text;
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_loading) return;
    final prompt = _prompt.text.trim();
    if (_action == DocumentAiAction.custom && prompt.isEmpty) {
      setState(() => _error = 'Write what you want the AI to do');
      return;
    }
    if (_source.trim().isEmpty && _action != DocumentAiAction.custom) {
      setState(() => _error = 'There is no text to work with yet');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _answer = null;
    });
    final action = _action;
    try {
      final result = await DocumentRepository.instance.ai(
        widget.documentId,
        action: action,
        selectedText: _source,
        prompt: action == DocumentAiAction.custom ? prompt : null,
      );
      if (!mounted) return;
      setState(() {
        _answer = result.trim();
        _answered = action;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    final canReplace = answer != null &&
        widget.canReplaceSelection &&
        _hasSelection &&
        (_answered?.replacesSelection ?? false) &&
        !answer.contains('\n');
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: orgTeal, size: 20),
              SizedBox(width: 8),
              Text('Ask AI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _hasSelection ? 'Working on your selected text.' : 'Working on the whole document.',
            style: const TextStyle(color: orgMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in DocumentAiAction.values)
                ChoiceChip(
                  selected: _action == a,
                  onSelected: _loading ? null : (_) => setState(() => _action = a),
                  avatar: Icon(a.icon, size: 16, color: _action == a ? Colors.white : orgMuted),
                  label: Text(a.label),
                  labelStyle: TextStyle(
                    color: _action == a ? Colors.white : orgMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: orgField,
                  selectedColor: orgAccent,
                  showCheckmark: false,
                  side: BorderSide(color: _action == a ? orgAccent : orgBorder),
                ),
            ],
          ),
          if (_action == DocumentAiAction.custom) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _prompt,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Turn this into a short announcement',
                hintStyle: const TextStyle(color: orgMuted),
                filled: true,
                fillColor: orgField,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _run,
              icon: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_action.icon, size: 18),
              label: Text(_loading ? 'Thinking…' : 'Generate', style: const TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: orgAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
          ],
          if (answer != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: orgField,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: orgBorder),
              ),
              child: SelectableText(answer, style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.5)),
            ),
            const SizedBox(height: 12),
            if (canReplace) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, DocumentAiResult(answer, replaceSelection: true)),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Replace selection', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: orgAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: answer.isEmpty ? null : () => Navigator.pop(context, DocumentAiResult(answer)),
                icon: const Icon(Icons.playlist_add_rounded, size: 18, color: orgTeal),
                label: const Text('Insert into document', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: orgBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DocumentWhiteboardPickerSheet extends StatefulWidget {
  const DocumentWhiteboardPickerSheet({super.key, this.meetingCode, this.organizationId});

  final String? meetingCode;
  final String? organizationId;

  @override
  State<DocumentWhiteboardPickerSheet> createState() => _DocumentWhiteboardPickerSheetState();
}

class _DocumentWhiteboardPickerSheetState extends State<DocumentWhiteboardPickerSheet> {
  List<Whiteboard> _boards = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = WhiteboardRepository.instance;
      final code = widget.meetingCode;
      final org = widget.organizationId;
      var boards = <Whiteboard>[];
      if (code != null && code.isNotEmpty) {
        boards = await repo.meetingBoards(code);
      }
      if (boards.isEmpty && org != null && org.isNotEmpty) {
        boards = (await repo.list(org, limit: 50)).items;
      }
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Embed whiteboard',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: orgTeal)),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13))
            else if (_boards.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No whiteboards available.', style: TextStyle(color: orgMuted))),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final b in _boards)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.draw_outlined, color: orgTeal),
                        title: Text(
                          b.name.isEmpty ? 'Whiteboard' : b.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        onTap: () => Navigator.pop(context, b),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

DocText markdownInline(String line) {
  final runs = <RichRun>[];
  final pattern = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
  var last = 0;
  for (final m in pattern.allMatches(line)) {
    if (m.start > last) runs.add(RichRun(line.substring(last, m.start)));
    if (m.group(1) != null) {
      runs.add(RichRun(m.group(1)!, [
        {'type': 'bold'},
      ]));
    } else {
      runs.add(RichRun(m.group(2)!, [
        {'type': 'code'},
      ]));
    }
    last = m.end;
  }
  if (last < line.length) runs.add(RichRun(line.substring(last)));
  return DocText.empty + DocText(runs);
}

List<DocBlock> markdownToBlocks(String markdown) {
  final out = <DocBlock>[];
  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
    final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
    final ordered = RegExp(r'^\s*\d+[.)]\s+(.*)$').firstMatch(line);
    if (heading != null) {
      out.add(DocBlock(
        type: DocBlockType.heading,
        level: heading.group(1)!.length,
        text: markdownInline(heading.group(2)!),
      ));
    } else if (bullet != null) {
      out.add(DocBlock(type: DocBlockType.bullet, text: markdownInline(bullet.group(1)!)));
    } else if (ordered != null) {
      out.add(DocBlock(type: DocBlockType.ordered, text: markdownInline(ordered.group(1)!)));
    } else {
      out.add(DocBlock(type: DocBlockType.paragraph, text: markdownInline(line.trim())));
    }
  }
  return out;
}