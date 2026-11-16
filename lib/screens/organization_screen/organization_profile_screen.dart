import 'package:flutter/material.dart';
import 'package:quorum_app/models/organization_models.dart';
import 'organization_widgets.dart';

class OrganizationProfileScreen extends StatelessWidget {
  const OrganizationProfileScreen({super.key, required this.organization});

  final Organization organization;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  Widget _stat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: orgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: orgBorder),
        ),
        child: Column(
          children: [
            Icon(icon, color: orgTeal, size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: orgMuted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: orgTeal, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(color: orgMuted, fontSize: 13))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final org = organization;
    final desc = org.description?.trim() ?? '';
    final created = org.createdAt;
    final industry = org.industry?.trim() ?? '';
    final teamSize = org.teamSize?.trim() ?? '';
    return Scaffold(
      backgroundColor: orgBg,
      appBar: AppBar(
        backgroundColor: orgBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Organization', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3A2D6B), Color(0xFF1E2A4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: orgBorder),
            ),
            child: Column(
              children: [
                OrgAvatar(name: org.name, logo: org.logo, size: 96),
                const SizedBox(height: 14),
                Text(
                  org.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                OrgRoleBadge(role: org.role),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    desc,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.45),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(Icons.people_alt_rounded, '${org.membersCount}', 'Members'),
              const SizedBox(width: 10),
              _stat(Icons.groups_rounded, '${org.teamsCount}', 'Teams'),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: orgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: orgBorder),
            ),
            child: Column(
              children: [
                if (created != null) _infoRow(Icons.calendar_today_rounded, 'Created', _date(created)),
                if (industry.isNotEmpty) _infoRow(Icons.business_center_outlined, 'Industry', industry),
                if (teamSize.isNotEmpty) _infoRow(Icons.diversity_3_rounded, 'Team size', teamSize),
                _infoRow(Icons.badge_outlined, 'Your role', orgRoleLabel(org.role)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}