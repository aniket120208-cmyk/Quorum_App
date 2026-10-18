import 'package:flutter/material.dart';
import 'bottom_nav_bar.dart';
import 'package:quorum_app/screens/chat_screen/chat_screen.dart';
import 'package:quorum_app/screens/ai_assistant_screen/ai_assistant_screen.dart';
import 'package:quorum_app/screens/community_screen/community_screen.dart';
import 'package:quorum_app/screens/video_call_screen/video_call_screen.dart';

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

class HomeScreen extends StatelessWidget{
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF090A10),
      body: Center(
        child: Text(
          'Home Screen',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}