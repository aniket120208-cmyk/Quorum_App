import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/current_user.dart';
import 'package:quorum_app/api/org_feed_repository.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/org_feed_models.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'org_feed_widgets.dart';
import 'organization_sheets.dart';
import 'organization_widgets.dart';

enum _Mode { festival, team, member, general }
enum _Tone { appreciation, concern }
enum _Occasion { birthday, promotion, appreciation }

const Set<String> _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};
const Set<String> _docExt = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv'};

String _extOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
}

InputDecoration _fieldDecoration(String hint) {
  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF5A5E6B)),
    filled: true,
    fillColor: orgField,
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(orgBorder),
    enabledBorder: border(orgBorder),
    focusedBorder: border(feedPurple),
  );
}

class OrgFeedComposerSheet extends StatefulWidget {
  const OrgFeedComposerSheet({
    super.key,
    required this.organization,
    required this.members,
    required this.teams,
  });

  final Organization organization;
  final List<OrgMember> members;
  final List<OrgTeam> teams;

  @override
  State<OrgFeedComposerSheet> createState() => _OrgFeedComposerSheetState();
}

class _OrgFeedComposerSheetState extends State<OrgFeedComposerSheet> {
  final _repo = OrgFeedRepository.instance;
  final _title = TextEditingController();
  final _content = TextEditingController();

  _Mode _mode = _Mode.general;
  OrgPostCategory _festivalCategory = OrgPostCategory.festival;
  _Tone _tone = _Tone.appreciation;
  _Occasion _occasion = _Occasion.birthday;
  String? _teamId;
  OrgMember? _member;
  Set<String> _mentions = {};
  String? _filePath;
  String? _fileName;
  int _fileBytes = 0;
  bool _pin = false;
  bool _busy = false;

  bool get _canManage => orgCanInvite(widget.organization.role);
  bool get _showsTitle => _mode != _Mode.general;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  OrgPostCategory _category() {
    switch (_mode) {
      case _Mode.festival:
        return _festivalCategory;
      case _Mode.team:
        return _tone == _Tone.appreciation ? OrgPostCategory.milestone : OrgPostCategory.announcement;
      case _Mode.member:
        switch (_occasion) {
          case _Occasion.birthday:
            return OrgPostCategory.birthday;
          case _Occasion.promotion:
            return OrgPostCategory.promotion;
          case _Occasion.appreciation:
            return OrgPostCategory.milestone;
        }
      case _Mode.general:
        return OrgPostCategory.general;
    }
  }

  Future<void> _attach() async {
    final choice = await showOrgSheet<String>(context, const _AttachChoiceSheet());
    if (choice == null) return;
    try {
      String? path;
      String? name;
      if (choice == 'photo') {
        final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
        path = x?.path;
        name = x?.name;
      } else {
        final f = await FilePicker.pickFile(type: FileType.any);
        path = f?.path;
        name = f?.name;
      }
      if (path == null || name == null) return;
      final ext = _extOf(name);
      if (!_imageExt.contains(ext) && !_docExt.contains(ext)) {
        if (mounted) orgToast(context, 'This file type is not supported.', error: true);
        return;
      }
      await UploadService.ensureWithinLimit(path, name);
      final bytes = await File(path).length();
      if (!mounted) return;
      setState(() {
        _filePath = path;
        _fileName = name;
        _fileBytes = bytes;
      });
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    }
  }

  void _clearFile() {
    setState(() {
      _filePath = null;
      _fileName = null;
      _fileBytes = 0;
    });
  }

  Future<void> _pickMember() async {
    final m = await showOrgSheet<OrgMember>(
      context,
      MemberPickerSheet(title: 'Select member', members: widget.members),
    );
    if (m != null && mounted) setState(() => _member = m);
  }

  Future<void> _pickMentions() async {
    final people = widget.members.where((m) => m.userId != CurrentUser.id).toList();
    final result = await showOrgSheet<Set<String>>(
      context,
      _MentionSheet(members: people, initial: _mentions),
    );
    if (result != null && mounted) setState(() => _mentions = result);
  }

  Future<void> _publish() async {
    if (_busy) return;
    final text = _content.text.trim();
    final title = _title.text.trim();
    if (_mode == _Mode.team && _teamId == null) {
      orgToast(context, 'Select a team first', error: true);
      return;
    }
    if (_mode == _Mode.member && _member == null) {
      orgToast(context, 'Select a member first', error: true);
      return;
    }
    if (text.isEmpty && _filePath == null) {
      orgToast(context, 'Write a message or attach a file', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      var post = await _repo.createPost(
        widget.organization.id,
        category: _category(),
        title: _showsTitle ? title : null,
        content: text,
        filePath: _filePath,
        fileName: _fileName,
        targetUserId: _mode == _Mode.member ? _member!.userId : null,
        targetTeamId: _mode == _Mode.team ? _teamId : null,
        mentionedUserIds: (_mode == _Mode.member || _mode == _Mode.general) ? _mentions.toList() : const [],
      );
      if (_pin && _canManage) {
        try {
          final pinned = await _repo.togglePin(widget.organization.id, post.id);
          if (pinned != false) post = post.copyWith(isPinned: true, pinnedAt: DateTime.now());
        } catch (e) {
          if (mounted) orgToast(context, 'Posted, but could not pin: ${errorText(e)}', error: true);
        }
      }
      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Select Post Type',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _modeGrid(),
                  const SizedBox(height: 16),
                  ..._fields(),
                  if (_filePath != null) ...[
                    const SizedBox(height: 12),
                    _filePreview(),
                  ],
                ],
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'New Organization Post',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : () => Navigator.pop(context),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: orgField, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeGrid() {
    final modes = [if (_canManage) _Mode.festival, _Mode.team, _Mode.member, _Mode.general];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final m in modes) SizedBox(width: w, child: _modeChip(m))],
        );
      },
    );
  }

  Widget _modeChip(_Mode m) {
    final selected = _mode == m;
    final (IconData icon, String label) = switch (m) {
      _Mode.festival => (Icons.celebration_rounded, 'Festival / Notice'),
      _Mode.team => (Icons.groups_rounded, 'Team Spotlight'),
      _Mode.member => (Icons.person_rounded, 'Member Spotlight'),
      _Mode.general => (Icons.chat_bubble_outline_rounded, 'General'),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _mode = m),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? feedPurple : orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? feedPurple : orgBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : orgMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : orgMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields() {
    switch (_mode) {
      case _Mode.festival:
        return [
          _segment<OrgPostCategory>(
            const [
              (OrgPostCategory.festival, Icons.celebration_rounded, 'Festival'),
              (OrgPostCategory.announcement, Icons.campaign_rounded, 'Announcement'),
            ],
            _festivalCategory,
            (v) => setState(() => _festivalCategory = v),
          ),
          const SizedBox(height: 12),
          _titleField(),
          const SizedBox(height: 12),
          _messageField('Write your wishes or notice...'),
        ];
      case _Mode.team:
        return [
          _teamDropdown(),
          const SizedBox(height: 12),
          _segment<_Tone>(
            const [
              (_Tone.appreciation, Icons.emoji_events_outlined, 'Appreciation'),
              (_Tone.concern, Icons.warning_amber_rounded, 'Concern'),
            ],
            _tone,
            (v) {
              if (v == _Tone.concern && !_canManage) {
                orgToast(context, 'Only admins and team heads can post updates or concerns', error: true);
                return;
              }
              setState(() => _tone = v);
            },
          ),
          const SizedBox(height: 12),
          _titleField(),
          const SizedBox(height: 12),
          _messageField('Write your message...'),
        ];
      case _Mode.member:
        return [
          _memberTile(),
          const SizedBox(height: 12),
          _segment<_Occasion>(
            const [
              (_Occasion.birthday, Icons.cake_outlined, 'Birthday'),
              (_Occasion.promotion, Icons.trending_up_rounded, 'Promotion'),
              (_Occasion.appreciation, Icons.favorite_border_rounded, 'Appreciation'),
            ],
            _occasion,
            (v) => setState(() => _occasion = v),
          ),
          const SizedBox(height: 12),
          _titleField(),
          const SizedBox(height: 12),
          _messageField('Write your message...'),
          const SizedBox(height: 12),
          _mentionTile(),
        ];
      case _Mode.general:
        return [
          _messageField('Share an update with the organization...'),
          const SizedBox(height: 12),
          _mentionTile(),
        ];
    }
  }

  Widget _segment<T>(List<(T, IconData, String)> items, T value, void Function(T) onChanged) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: orgField,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: orgBorder),
      ),
      child: Row(
        children: [
          for (final (v, icon, label) in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onChanged(v),
                child: Container(
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == v ? feedPurple.withValues(alpha: 0.22) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: value == v ? feedPurple : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 15, color: value == v ? Colors.white : orgMuted),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: value == v ? Colors.white : orgMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _teamDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: orgField,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: orgBorder),
      ),
      child: widget.teams.isEmpty
          ? const SizedBox(
              height: 48,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('No teams yet', style: TextStyle(color: orgMuted)),
              ),
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _teamId,
                isExpanded: true,
                dropdownColor: orgCard,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: orgMuted),
                hint: const Text('Select team', style: TextStyle(color: orgMuted, fontSize: 14)),
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                items: [
                  for (final t in widget.teams)
                    DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _teamId = v),
              ),
            ),
    );
  }

  Widget _memberTile() {
    final m = _member;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pickMember,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            if (m != null) ...[
              OrgAvatar(name: m.name, logo: m.avatar, size: 28, circular: true),
              const SizedBox(width: 10),
            ] else ...[
              const Icon(Icons.person_search_rounded, color: orgMuted, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                m?.name ?? 'Select member',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: m == null ? orgMuted : Colors.white,
                  fontSize: 14,
                  fontWeight: m == null ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: orgMuted),
          ],
        ),
      ),
    );
  }

  Widget _mentionTile() {
    final names = [
      for (final m in widget.members)
        if (_mentions.contains(m.userId)) m.name,
    ];
    final label = names.isEmpty
        ? 'Mention people (optional)'
        : names.length <= 2
            ? names.join(', ')
            : '${names.take(2).join(', ')} +${names.length - 2}';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _pickMentions,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: orgField,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: orgBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.alternate_email_rounded, color: names.isEmpty ? orgMuted : feedPurple, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: names.isEmpty ? orgMuted : Colors.white, fontSize: 14),
              ),
            ),
            if (names.isNotEmpty)
              InkWell(
                onTap: () => setState(() => _mentions = {}),
                child: const Icon(Icons.close_rounded, color: orgMuted, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _titleField() {
    return TextField(
      controller: _title,
      maxLength: 160,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: feedPurple,
      decoration: _fieldDecoration('Title'),
    );
  }

  Widget _messageField(String hint) {
    return TextField(
      controller: _content,
      maxLength: 10000,
      minLines: 5,
      maxLines: 8,
      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
      cursorColor: feedPurple,
      decoration: _fieldDecoration(hint),
    );
  }

  Widget _filePreview() {
    final name = _fileName ?? 'Attachment';
    final isImage = _imageExt.contains(_extOf(name));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: orgField,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: orgBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 46,
              height: 46,
              child: isImage
                  ? Image.file(File(_filePath!), fit: BoxFit.cover)
                  : Container(
                      color: feedPurple.withValues(alpha: 0.16),
                      child: const Icon(Icons.insert_drive_file_outlined, color: feedPurple),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(orgFeedFileSize(_fileBytes), style: const TextStyle(color: orgMuted, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: _busy ? null : _clearFile,
            icon: const Icon(Icons.close_rounded, color: orgMuted, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: orgBorder))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Attach',
                onPressed: _busy ? null : _attach,
                icon: Icon(
                  Icons.attach_file_rounded,
                  color: _filePath == null ? orgMuted : feedPurple,
                  size: 22,
                ),
              ),
              const Spacer(),
              if (_canManage) ...[
                const Icon(Icons.push_pin_outlined, color: orgMuted, size: 16),
                const SizedBox(width: 6),
                const Text('Pin to top', style: TextStyle(color: orgMuted, fontSize: 12.5)),
                const SizedBox(width: 4),
                Switch(
                  value: _pin,
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? feedPurple : orgField,
                  ),
                  onChanged: _busy ? null : (v) => setState(() => _pin = v),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _busy ? null : _publish,
              style: ElevatedButton.styleFrom(
                backgroundColor: feedPurple,
                disabledBackgroundColor: feedPurple.withValues(alpha: 0.5),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Publish', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachChoiceSheet extends StatelessWidget {
  const _AttachChoiceSheet();

  @override
  Widget build(BuildContext context) {
    Widget option(IconData icon, String label, String value) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: feedPurple.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: feedPurple, size: 21),
        ),
        title: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onTap: () => Navigator.pop(context, value),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Attach', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          option(Icons.image_outlined, 'Photo or poster', 'photo'),
          option(Icons.insert_drive_file_outlined, 'Document', 'file'),
        ],
      ),
    );
  }
}

class _MentionSheet extends StatefulWidget {
  const _MentionSheet({required this.members, required this.initial});
  final List<OrgMember> members;
  final Set<String> initial;

  @override
  State<_MentionSheet> createState() => _MentionSheetState();
}

class _MentionSheetState extends State<_MentionSheet> {
  late final Set<String> _selected = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.members
        : widget.members.where((m) => m.name.toLowerCase().contains(q) || (m.email ?? '').toLowerCase().contains(q)).toList();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Mention people',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text('${_selected.length}/25', style: const TextStyle(color: orgMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              cursorColor: feedPurple,
              decoration: _fieldDecoration('Search members').copyWith(
                prefixIcon: const Icon(Icons.search_rounded, color: orgMuted, size: 20),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No members found', style: TextStyle(color: orgMuted))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final m = list[i];
                        final on = _selected.contains(m.userId);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: OrgAvatar(name: m.name, logo: m.avatar, size: 38, circular: true),
                          title: Text(m.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          trailing: Icon(
                            on ? Icons.check_circle_rounded : Icons.circle_outlined,
                            color: on ? feedPurple : orgMuted,
                          ),
                          onTap: () => setState(() {
                            if (on) {
                              _selected.remove(m.userId);
                            } else if (_selected.length < 25) {
                              _selected.add(m.userId);
                            }
                          }),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _selected),
                style: ElevatedButton.styleFrom(
                  backgroundColor: feedPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrgFeedEditSheet extends StatefulWidget {
  const OrgFeedEditSheet({super.key, required this.organizationId, required this.post});
  final String organizationId;
  final OrgFeedPost post;

  @override
  State<OrgFeedEditSheet> createState() => _OrgFeedEditSheetState();
}

class _OrgFeedEditSheetState extends State<OrgFeedEditSheet> {
  late final _title = TextEditingController(text: widget.post.title ?? '');
  late final _content = TextEditingController(text: widget.post.content);
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final text = _content.text.trim();
    if (text.isEmpty && !widget.post.hasFile) {
      orgToast(context, 'Message cannot be empty', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await OrgFeedRepository.instance.editPost(
        widget.organizationId,
        widget.post.id,
        title: _title.text,
        content: text,
      );
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      orgToast(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Edit post', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            maxLength: 160,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: feedPurple,
            decoration: _fieldDecoration('Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            maxLength: 10000,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            cursorColor: feedPurple,
            decoration: _fieldDecoration('Write your message...'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: feedPurple,
                disabledBackgroundColor: feedPurple.withValues(alpha: 0.5),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save changes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}