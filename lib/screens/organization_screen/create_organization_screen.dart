import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/organization_repository.dart';
import 'package:quorum_app/api/upload_service.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key});

  @override
  State<CreateOrganizationScreen> createState() => _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _logoPath;
  String? _logoName;
  bool _loading = false;

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
    setState(() {
      _logoPath = picked.path;
      _logoName = picked.name;
    });
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      String? logoUrl;
      if (_logoPath != null) {
        final res = await UploadService.instance.upload(path: _logoPath!, fileName: _logoName ?? 'logo.jpg');
        logoUrl = res.url;
      }
      final org = await OrganizationRepository.instance.create(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        logo: logoUrl,
      );
      if (!mounted) return;
      orgToast(context, 'Organization created');
      Navigator.pop<Organization>(context, org);
    } catch (e) {
      if (mounted) orgToast(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Create Organization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: OrgLogoPicker(
                    name: _nameCtrl.text,
                    pickedPath: _logoPath,
                    onTap: _pickLogo,
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Add a logo (optional)', style: TextStyle(color: orgMuted, fontSize: 12)),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.words,
                  decoration: orgInputDecoration('Organization name', hint: 'e.g. Acme Corporation'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Organization name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  style: const TextStyle(color: Colors.white),
                  minLines: 3,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: orgInputDecoration('Description (optional)', hint: 'What does your organization do?'),
                ),
                const SizedBox(height: 28),
                OrgPrimaryButton(label: 'Create organization', loading: _loading, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}