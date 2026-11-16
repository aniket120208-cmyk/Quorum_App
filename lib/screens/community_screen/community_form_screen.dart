import 'package:flutter/material.dart';
import 'package:quorum_app/form_validators.dart';
import 'package:quorum_app/screens/chat_screen/chat_widgets.dart';
import 'package:quorum_app/screens/community_screen/community_widgets.dart';

class CommunityFormScreen extends StatefulWidget {
  const CommunityFormScreen({
    super.key,
    this.title = 'New community',
    this.actionLabel = 'Create',
  });

  final String title;
  final String actionLabel;

  @override
  State<CommunityFormScreen> createState() => _CommunityFormScreenState();
}

class _CommunityFormScreenState extends State<CommunityFormScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  String? _nameError;
  String? _descError;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final description = _desc.text.trim();
    String? nameError;
    if (name.isEmpty) {
      nameError = 'Give your community a name.';
    } else {
      nameError = FormValidators.communityName(name);
    }
    final descError = FormValidators.communityDescription(description);
    if (nameError != null || descError != null) {
      setState(() {
        _nameError = nameError;
        _descError = descError;
      });
      return;
    }
    Navigator.pop(context, (name, description));
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );

  Widget _error(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F101A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F101A),
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          widget.title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Name'),
                    TextField(
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: communityFieldDecoration('Community name'),
                    ),
                    _error(_nameError),
                    const SizedBox(height: 20),
                    _label('Description'),
                    TextField(
                      controller: _desc,
                      minLines: 4,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: communityFieldDecoration('What is this community about?'),
                    ),
                    _error(_descError),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(widget.actionLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}