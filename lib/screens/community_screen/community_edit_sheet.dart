import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/community_repository.dart';
import 'package:quorum_app/api/profile_picture_repository.dart';
import 'package:quorum_app/form_validators.dart';
import 'package:quorum_app/models/community_models.dart';
import 'package:quorum_app/screens/organization_screen/organization_widgets.dart';

class EditCommunitySheet extends StatefulWidget {
  const EditCommunitySheet({super.key, required this.community});
  final CommunityDetail community;

  @override
  State<EditCommunitySheet> createState() => _EditCommunitySheetState();
}

class _EditCommunitySheetState extends State<EditCommunitySheet> {
  late final _nameCtrl = TextEditingController(text: widget.community.name);
  late final _descCtrl = TextEditingController(text: widget.community.description ?? '');
  String? _logoPath;
  String? _logoName;
  String? _nameError;
  String? _descError;
  bool _loading = false;
  bool _removeLogo = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await pickOrgLogo();
    if (picked == null || !mounted) return;
    final problem = await ProfilePictureRepository.validateFile(picked.path, picked.name);
    if (!mounted) return;
    if (problem != null) {
      orgToast(context, problem, error: true);
      return;
    }
    setState(() {
      _logoPath = picked.path;
      _logoName = picked.name;
      _removeLogo = false;
    });
  }

  Future<void> _save() async {
    if (_loading) return;
    final name = _nameCtrl.text.trim();
    final description = _descCtrl.text.trim();
    final nameError = name.isEmpty ? 'Give your community a name.' : FormValidators.communityName(name);
    final descError = FormValidators.communityDescription(description);
    if (nameError != null || descError != null) {
      setState(() {
        _nameError = nameError;
        _descError = descError;
      });
      return;
    }
    setState(() {
      _nameError = null;
      _descError = null;
      _loading = true;
    });
    try {
      await CommunityRepository.instance.updateCommunity(
        widget.community.id,
        name: name,
        description: description,
      );
      final pictures = ProfilePictureRepository.instance;
      if (_logoPath != null) {
        await pictures.uploadFile(
          ProfilePictureTarget.community,
          widget.community.id,
          path: _logoPath!,
          fileName: _logoName ?? 'logo.jpg',
        );
      } else if (_removeLogo) {
        await pictures.remove(ProfilePictureTarget.community, widget.community.id);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrent = !_removeLogo && (widget.community.avatar ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 18),
            child: Text(
              'Edit community',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          Center(
            child: OrgLogoPicker(
              name: _nameCtrl.text,
              currentLogo: _removeLogo ? null : widget.community.avatar,
              pickedPath: _logoPath,
              onTap: _pickLogo,
            ),
          ),
          if (_logoPath != null || hasCurrent)
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  if (_logoPath != null) {
                    _logoPath = null;
                    _logoName = null;
                  } else {
                    _removeLogo = true;
                  }
                }),
                child: Text(
                  _logoPath != null ? 'Discard new photo' : 'Remove photo',
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: orgInputDecoration('Community name').copyWith(errorText: _nameError),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _descCtrl,
            style: const TextStyle(color: Colors.white),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: orgInputDecoration('Description').copyWith(errorText: _descError),
          ),
          const SizedBox(height: 22),
          OrgPrimaryButton(label: 'Save', loading: _loading, onPressed: _save),
        ],
      ),
    );
  }
}