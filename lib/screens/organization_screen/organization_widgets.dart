import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

const Color orgBg = Color(0xFF090A10);
const Color orgCard = Color(0xFF14151F);
const Color orgField = Color(0xFF1B1D2A);
const Color orgBorder = Color(0x1AFFFFFF);
const Color orgTeal = Color(0xFF3DDCC4);
const Color orgMuted = Color(0xFF9EA3AE);
const Color orgAccent = Color(0xFF4C3AE3);

Future<XFile?> pickOrgLogo() => ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);

class OrgAvatar extends StatelessWidget {
  const OrgAvatar({
    super.key,
    required this.name,
    this.logo,
    this.localPath,
    this.size = 44,
    this.circular = false,
  });

  final String name;
  final String? logo;
  final String? localPath;
  final double size;
  final bool circular;

  Widget _initial() {
    final trimmed = name.trim();
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFF7C5CFC),
      child: Text(
        trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (localPath != null) {
      child = Image.file(File(localPath!), fit: BoxFit.cover, width: size, height: size);
    } else if (logo != null && logo!.isNotEmpty) {
      child = Image.network(
        logo!,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stack) => _initial(),
      );
    } else {
      child = _initial();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(circular ? size / 2 : size * 0.3),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

class OrgRoleBadge extends StatelessWidget {
  const OrgRoleBadge({super.key, required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (role) {
      case 'ORG_ADMIN':
        color = const Color(0xFFF59E0B);
        label = 'Admin';
      case 'TEAM_HEAD':
        color = orgTeal;
        label = 'Team Head';
      default:
        color = orgMuted;
        label = 'Member';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class OrgLogoPicker extends StatelessWidget {
  const OrgLogoPicker({
    super.key,
    required this.name,
    this.currentLogo,
    this.pickedPath,
    required this.onTap,
  });

  final String name;
  final String? currentLogo;
  final String? pickedPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          OrgAvatar(name: name, logo: currentLogo, localPath: pickedPath, size: 88),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: orgAccent,
                shape: BoxShape.circle,
                border: Border.all(color: orgBg, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class OrgPrimaryButton extends StatelessWidget {
  const OrgPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: orgAccent,
          disabledBackgroundColor: orgAccent.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white60,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

InputDecoration orgInputDecoration(String label, {String? hint}) {
  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: orgMuted),
    hintStyle: const TextStyle(color: Color(0xFF5A5E6B)),
    filled: true,
    fillColor: orgField,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(const Color(0xFF2C3246)),
    enabledBorder: border(const Color(0xFF2C3246)),
    focusedBorder: border(const Color(0xFF5663F6)),
    errorBorder: border(const Color(0xFFEF4444)),
    focusedErrorBorder: border(const Color(0xFFEF4444)),
  );
}

void orgToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? Colors.redAccent : const Color(0xFF1F2937),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<bool> orgConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: orgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(body, style: const TextStyle(color: orgMuted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: orgMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action, style: const TextStyle(color: Color(0xFFEF4444))),
        ),
      ],
    ),
  );
  return ok == true;
}

const RoundedRectangleBorder orgSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);