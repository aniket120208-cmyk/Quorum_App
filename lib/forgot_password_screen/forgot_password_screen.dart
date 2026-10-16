import 'dart:async';
import 'package:flutter/material.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  AutovalidateMode _autoValidateMode = AutovalidateMode.disabled;
  bool _isEmailFilled = false;
  String _displayEmail = 'example@company.com';
  Timer? _timer;
  int _secondsRemaining = 30;
  bool _canResend = false;

  final RegExp _emailRegex =  RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_handleEmailChange);
    _startCountdown();
  }

  void _handleEmailChange() {
    final text = _emailController.text.trim();
    final isFilled = text.isNotEmpty;
    if (_isEmailFilled != isFilled) {
      setState(() {
        _isEmailFilled = isFilled;
      });
    }
    setState(() {
      _displayEmail = text.isEmpty ? 'example@company.com' : text;
    });
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() {
      _secondsRemaining = 30;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.removeListener(_handleEmailChange);
    _emailController.dispose();
    super.dispose();
  }

  void _submitForm() {
    if (_formKey.currentState?.validate() ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP sent successfully!'),
        ),
      );
    } else {
      setState(() {
        _autoValidateMode = AutovalidateMode.onUserInteraction;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A10),
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: _autoValidateMode,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 36),
                            const Text(
                              'Forgot your password',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: Color(0xFF8E95A9),
                                  fontSize: 15,
                                  height: 1.35,
                                ),
                                children: [
                                  const TextSpan(
                                    text: "We'll send an email verification OTP to\n",
                                  ),
                                  TextSpan(
                                    text: _displayEmail,
                                    style: const TextStyle(
                                      color: Color(0xFF5663F6),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 44),
                            Center(
                              child: Container(
                                width: 105,
                                height: 105,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222854),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned(
                                      top: 18,
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF5663F6),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.lock_rounded,
                                            color: Color(0xFF222854),
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 18,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          '*****',
                                          style: TextStyle(
                                            color: Color(0xFF1E2140),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 44),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F1118).withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: const Color(0xFF2C3246),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Work email',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    cursorColor: const Color(0xFF4C4FE8),
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) {
                                        return 'Email is required';
                                      }
                                      if (!_emailRegex.hasMatch(text)) {
                                        return 'Enter a valid email address';
                                      }
                                      return null;
                                    },
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: const Color(0xFF1E212A),
                                      hintText: 'example@gmail.com',
                                      hintStyle: const TextStyle(
                                        color: Color(0xFF575D71),
                                        fontSize: 14,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.mail_outline_rounded,
                                        color: Color(0xFF7E8497),
                                        size: 20,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 16,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF4C4FE8),
                                          width: 1.2,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE53935),
                                          width: 1.2,
                                        ),
                                      ),
                                      focusedErrorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE53935),
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        "Didn't receive the link?",
                                        style: TextStyle(
                                          color: Color(0xFF8E95A9),
                                          fontSize: 13,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _canResend ? _startCountdown : null,
                                        child: Text(
                                          _canResend
                                              ? 'Resend'
                                              : 'Resend (${_secondsRemaining}s)',
                                          style: TextStyle(
                                            color: _canResend ? const Color(0xFF5663F6) : const Color(0xFF8E95A9),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isEmailFilled ? _submitForm : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF3B4AF5),
                                        disabledBackgroundColor: const Color(0xFF2E337A).withValues(alpha: 0.45),
                                        disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: const Text(
                                        'Send Otp',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}