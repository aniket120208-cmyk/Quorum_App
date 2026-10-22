import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quorum_app/api/api_exception.dart';
import 'package:quorum_app/api/auth_service.dart';
import 'package:quorum_app/screens/home_screen/home_screen.dart';
import 'package:quorum_app/screens/sign_in_screen/sign_in_screen.dart';
import 'package:quorum_app/screens/use_case_screen/use_case_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String? password;
  const VerifyEmailScreen({required this.email, this.password, super.key});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  int _resendSeconds = 30;
  Timer? _timer;
  bool _isVerifying = false;
  bool _isResending = false;
  bool get _isOtpComplete => _otpControllers.every((c) => c.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    for (final controller in _otpControllers) {
      controller.addListener(() => setState(() {}));
    }
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds > 0) {
        setState(() => _resendSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  void _handleOtpPaste(String pastedText) {
    final digits = pastedText.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    for (int i = 0; i < 6; i++) {
      if (i < digits.length) {
        _otpControllers[i].text = digits[i];
      }
    }
    final focusIndex = (digits.length >= 6) ? 5 : digits.length;
    _otpFocusNodes[focusIndex].requestFocus();
    setState(() {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resend() async {
    if (_isResending) return;
    setState(() => _isResending = true);
    try {
      await AuthService.instance.sendVerificationOtp(widget.email);
      if (!mounted) return;
      _startResendTimer();
      _showMessage('A new code has been sent to ${widget.email}');
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _openNext(bool isOnboarded) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => isOnboarded ? const MainNavigationScreen() : const UseCaseScreen(),
      ),
      (_) => false,
    );
  }

  Future<void> _verify() async {
    if (!_isOtpComplete || _isVerifying) return;
    setState(() => _isVerifying = true);
    try {
      final otp = _otpControllers.map((c) => c.text).join();
      var result = await AuthService.instance.verifyEmail(email: widget.email, otp: otp);
      if (!result.authenticated && widget.password != null) {
        result = await AuthService.instance.login(email: widget.email, password: widget.password!);
      }
      if (!mounted) return;
      if (result.authenticated) {
        _openNext(result.isOnboarded);
      } else {
        _showMessage('Email verified. Please sign in.');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SignInScreen()),
          (_) => false,
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090A10),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              IconButton(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                'Verify your email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF9E9EA7),
                    fontSize: 15,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: "We've sent a 6-digit code to\n"),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                        color: Color(0xFF5D5FEF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF13151B).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF262A34),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Verification code',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) => _buildOtpField(index)),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Didn't receive the code?",
                          style: TextStyle(
                            color: Color(0xFF9E9EA7),
                            fontSize: 13,
                          ),
                        ),
                        GestureDetector(
                          onTap: (_resendSeconds == 0 && !_isResending) ? _resend : null,
                          child: Text(
                            _resendSeconds > 0 ? 'Resend (${_resendSeconds}s)' : 'Resend',
                            style: TextStyle(
                              color: _resendSeconds > 0
                                  ? const Color(0xFF9E9EA7)
                                  : const Color(0xFF5D5FEF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (_isOtpComplete && !_isVerifying) ? _verify : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4C3AE3),
                          disabledBackgroundColor: const Color(0xFF4C3AE3).withValues(alpha: 0.5),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white60,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Verify email',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
    );
  }

  Widget _buildOtpField(int index) {
    return SizedBox(
      width: 44,
      height: 48,
      child: TextFormField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        inputFormatters: [
          LengthLimitingTextInputFormatter(6),
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF22252D),
          hintText: 'x',
          hintStyle: const TextStyle(
            color: Color(0xFF5A5E6B),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF323642), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF323642), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF5D5FEF), width: 1.5),
          ),
        ),
        onChanged: (value) {
          if (value.length > 1) {
            _handleOtpPaste(value);
            return;
          }
          if (value.isNotEmpty && index < 5) {
            _otpFocusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _otpFocusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }
}