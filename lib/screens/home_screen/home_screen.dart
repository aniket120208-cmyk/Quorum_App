import 'package:flutter/material.dart';
import 'bottom_nav_bar.dart';
import 'package:quorum_app/screens/chat_screen/chat_screen.dart';
import 'package:quorum_app/screens/ai_assistant_screen/ai_assistant_screen.dart';
import 'package:quorum_app/screens/community_screen/community_screen.dart';
import 'package:quorum_app/screens/video_call_screen/video_call_screen.dart';
import 'calender_card.dart';

const _card = Color(0xFF14151F);
const _cardBorder = Color(0x1AFFFFFF);
const _teal = Color(0xFF3DDCC4);
const _muted = Color(0xFF9EA3AE);

String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    return 'Good evening';
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    ChatScreen(),
    VideoCallScreen(),
    CommunityScreen(),
    AIAssistantScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F101A),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget{
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final userName = 'User';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF090A10),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 22),
              Text(
                '${_getTimeGreeting()}, $userName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Here is what is happening across your teams today.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _buildHero(),
              const SizedBox(height: 22),
              _buildWorkspaceActions(),
              const SizedBox(height: 12),
              _buildFreelanceCard(),
              const SizedBox(height: 16),
              CalendarCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        height: 150,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3A2D6B), Color(0xFF1E2A4A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -10,
              child: Container(
                width: 110,
                height: 110,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF6C4BE0), Color(0xFF3B2A93)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 70,
              top: 28,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(color: Color(0xFFF5B83D), shape: BoxShape.circle),
              ),
            ),
            Positioned(
              right: -30,
              bottom: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(color: Color(0xFF1F7F86), shape: BoxShape.circle),
              ),
            ),
            Positioned(
              right: 40,
              bottom: 18,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: Color(0xFF3DB6A8), shape: BoxShape.circle),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Build, collaborate, make\nit happen.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Plan, create, collaborate and turn\nyour vision into reality.',
                    style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Workspace Actions',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _actionCard(
                  icon: Icons.add_business_outlined,
                  title: 'Create\nOrganization',
                  subtitle: 'Start your company or department hub',
                  cta: 'Build now',
                  onTap: (){},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionCard(
                  icon: Icons.group_add_outlined,
                  title: 'Join\nOrganization',
                  subtitle: 'Connect via direct invite links or id/QR code',
                  cta: 'Enter code',
                  onTap: (){},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String cta,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBox(icon),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11, height: 1.35)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cta,
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    decorationColor: _teal,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward, color: _teal, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFreelanceCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconBox(Icons.work_outline_rounded),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Freelance & Contractor',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Join client workspaces with guest permissions',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(color: _cardBorder),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('No organisation account needed', style: TextStyle(color: _muted, fontSize: 11)),
              GestureDetector(
                onTap: () {},
                child: const Row(
                  children: [
                    Text(
                      'Join Workspace',
                      style: TextStyle(
                        color: _teal,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        decorationColor: _teal,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, color: _teal, size: 14),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      );

  Widget _iconBox(IconData icon, {double size = 40}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF16302F),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: _teal, size: size * 0.5),
      );
}