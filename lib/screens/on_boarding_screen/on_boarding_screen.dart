import 'dart:async';
import 'package:flutter/material.dart';
import 'package:quorum_app/screens/sign_in_screen/sign_in_screen.dart';

class FeatureItem {
  final IconData icon;
  final String title;
  final String subtitle;

  const FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _baseOffset = 10000;
  late final PageController _pageController;
  Timer? _autoScrollTimer;
  int _virtualIndex = _baseOffset;

  final List<FeatureItem> _features = const [
    FeatureItem(
      icon: Icons.videocam_rounded,
      title: 'Video Meetings',
      subtitle: 'Turn ideas into action',
    ),
    FeatureItem(
      icon: Icons.folder_rounded,
      title: 'Files Sharing',
      subtitle: 'Access, share, collab',
    ),
    FeatureItem(
      icon: Icons.chat_bubble_rounded,
      title: 'Team Chat',
      subtitle: 'Stay connected anywhere',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: _virtualIndex,
      viewportFraction: 0.78,
    );
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_pageController.hasClients) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A10),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final imageSize = (availableWidth - 48).clamp(180.0, 310.0);
            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          SizedBox(height: 24),
                          Text(
                            'Work better\ntogether with',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              height: 1.15,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Quorum',
                            style: TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Center(
                          child: SizedBox(
                            width: imageSize,
                            height: imageSize,
                            child: Image.asset(
                              'lib/assets/q.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          SizedBox(
                            height: 68,
                            child: Listener(
                              onPointerDown: (_) => _autoScrollTimer?.cancel(),
                              onPointerUp: (_) => _startAutoScroll(),
                              child: PageView.builder(
                                controller: _pageController,
                                physics: const BouncingScrollPhysics(),
                                clipBehavior: Clip.none,
                                onPageChanged: (index) {
                                  setState(() {
                                    _virtualIndex = index;
                                  });
                                },
                                itemBuilder: (context, index) {
                                  final item =  _features[index % _features.length];
                                  final isSelected = index == _virtualIndex;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6.0,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF13161F),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: isSelected ? const Color(0xFF262A38) : Colors.transparent,
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            item.icon,
                                            color: const Color(0xFF4D6CFA),
                                            size: 24,
                                          ),
                                          if (isSelected) ...[
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment:  MainAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    item.title,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    item.subtitle,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0xFF71788E),
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SignInScreen(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E5BFF),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Get Started',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}