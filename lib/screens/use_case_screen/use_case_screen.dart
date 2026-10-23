import 'package:flutter/material.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/screens/home_screen/home_screen.dart';

class _UseCaseOption {
  final String value;
  final IconData icon;
  final String title;
  final String subtitle;
  const _UseCaseOption({
    required this.value,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class UseCaseScreen extends StatefulWidget {
  const UseCaseScreen({super.key});
  @override
  State<UseCaseScreen> createState() => _UseCaseScreenState();
}

class _UseCaseScreenState extends State<UseCaseScreen> {
  static const List<_UseCaseOption> _options = [
    _UseCaseOption(
      value: 'ORGANIZATION',
      icon: Icons.business_center_rounded,
      title: 'Work at an Organization',
      subtitle: 'Meetings, chat and files for your team',
    ),
    _UseCaseOption(
      value: 'FREELANCE',
      icon: Icons.laptop_mac_rounded,
      title: 'Freelance',
      subtitle: 'Manage clients and projects on your own',
    ),
    _UseCaseOption(
      value: 'HIRE_COLLABORATE',
      icon: Icons.group_add_rounded,
      title: 'Hire & Collaborate',
      subtitle: 'Find people and build together',
    ),
    _UseCaseOption(
      value: 'COMMUNITY',
      icon: Icons.forum_rounded,
      title: 'Communities',
      subtitle: 'Join and grow communities',
    ),
  ];

  final Set<String> _selected = {};
  bool _isSaving = false;

  void _toggle(String value) {
    setState(() {
      if (!_selected.remove(value)) {
        _selected.add(value);
      }
    });
  }

  Future<void> _save(List<String> useCases) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await AuthService.instance.saveOnboarding(useCases);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A10),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              const Text(
                'How do you want to\nuse Quorum?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Select all that apply',
                style: TextStyle(
                  color: Color(0xFF8E95A9),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView.separated(
                  physics: const ClampingScrollPhysics(),
                  itemCount: _options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _buildOption(_options[index]),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_selected.isNotEmpty && !_isSaving)
                      ? () => _save(_options
                          .where((o) => _selected.contains(o.value))
                          .map((o) => o.value)
                          .toList())
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C3AE3),
                    disabledBackgroundColor: const Color(0xFF4C3AE3).withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white60,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isSaving ? null : () => _save(const []),
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: Color(0xFF8E95A9),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(_UseCaseOption option) {
    final isSelected = _selected.contains(option.value);
    return GestureDetector(
      onTap: _isSaving ? null : () => _toggle(option.value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF4C3AE3).withValues(alpha: 0.15)
              : const Color(0xFF0F1118).withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF5663F6) : const Color(0xFF2C3246),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF222854),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(option.icon, color: const Color(0xFF6366F1), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    option.subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8E95A9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: isSelected ? const Color(0xFF5663F6) : const Color(0xFF575D71),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
