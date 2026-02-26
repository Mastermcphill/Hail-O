import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/role_routes.dart';
import '../../widgets/loading_overlay.dart';
import 'data/auth_api.dart';
import 'session/auth_session.dart';

enum _AuthMode { otp, email }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.nextPath});

  final String? nextPath;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpCodeController = TextEditingController();

  _AuthMode _mode = _AuthMode.otp;
  bool _isLoading = false;
  bool _otpRequested = false;
  String? _errorMessage;
  String? _infoMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpCodeController.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (_mode == mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _errorMessage = null;
      _infoMessage = null;
      if (mode == _AuthMode.email) {
        _otpRequested = false;
      }
    });
  }

  Future<void> _loginWithEmail() async {
    final form = _emailFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final authSession = context.read<AuthSession>();
      final session = await authSession.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) {
        return;
      }
      context.go(
        resolvePostLoginRoute(role: session.role, nextPath: widget.nextPath),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = mapLoginErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.trim();
    if (!_looksLikePhoneE164(phone)) {
      setState(() {
        _errorMessage = 'Enter a valid E.164 phone number, e.g. +2348012345678';
        _infoMessage = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await context.read<AuthSession>().requestOtp(phone);
      if (!mounted) {
        return;
      }
      setState(() {
        _otpRequested = true;
        _infoMessage = 'OTP sent. Enter the code to continue.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = mapOtpErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final phone = _phoneController.text.trim();
    final code = _otpCodeController.text.trim();
    if (!_looksLikePhoneE164(phone)) {
      setState(() {
        _errorMessage = 'Enter a valid E.164 phone number, e.g. +2348012345678';
        _infoMessage = null;
      });
      return;
    }
    if (!_looksLikeOtpCode(code)) {
      setState(() {
        _errorMessage = 'Enter the OTP code.';
        _infoMessage = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final session = await context.read<AuthSession>().verifyOtp(
        phoneE164: phone,
        code: code,
      );
      if (!mounted) {
        return;
      }
      context.go(
        resolvePostLoginRoute(role: session.role, nextPath: widget.nextPath),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = mapOtpErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: _mode == _AuthMode.otp
            ? 'Verifying code...'
            : 'Signing you in...',
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    height: 52,
                    child: Image.asset(
                      'assets/brand/logo_mark.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.local_taxi,
                        size: 36,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<_AuthMode>(
                    segments: const <ButtonSegment<_AuthMode>>[
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.otp,
                        label: Text('Phone OTP'),
                      ),
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.email,
                        label: Text('Email'),
                      ),
                    ],
                    selected: <_AuthMode>{_mode},
                    onSelectionChanged: (selection) {
                      final selected = selection.first;
                      _switchMode(selected);
                    },
                  ),
                  const SizedBox(height: 20),
                  if (_mode == _AuthMode.email) ...<Widget>[
                    Form(
                      key: _emailFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const <String>[AutofillHints.email],
                            validator: (value) {
                              final email = (value ?? '').trim();
                              if (email.isEmpty) {
                                return 'Email is required';
                              }
                              if (!_looksLikeEmail(email)) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            autofillHints: const <String>[
                              AutofillHints.password,
                            ],
                            onFieldSubmitted: (_) =>
                                _isLoading ? null : _loginWithEmail(),
                            validator: (value) {
                              if ((value ?? '').isEmpty) {
                                return 'Password is required';
                              }
                              return null;
                            },
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            label: 'Sign in button',
                            button: true,
                            child: FilledButton(
                              onPressed: _isLoading ? null : _loginWithEmail,
                              child: const Text('Sign in'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...<Widget>[
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: _otpRequested
                          ? TextInputAction.next
                          : TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Phone (E.164)',
                        hintText: '+2348012345678',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_otpRequested) ...<Widget>[
                      TextField(
                        controller: _otpCodeController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _isLoading ? null : _verifyOtp(),
                        decoration: const InputDecoration(
                          labelText: 'OTP code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _isLoading ? null : _verifyOtp,
                        child: const Text('Verify code'),
                      ),
                      TextButton(
                        onPressed: _isLoading ? null : _requestOtp,
                        child: const Text('Resend code'),
                      ),
                    ] else ...<Widget>[
                      FilledButton(
                        onPressed: _isLoading ? null : _requestOtp,
                        child: const Text('Request OTP'),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  Semantics(
                    label: 'Create account button',
                    button: true,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.go('/signup'),
                      child: const Text('Create account'),
                    ),
                  ),
                  Semantics(
                    label: 'Admin login button',
                    button: true,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.go('/admin-login'),
                      child: const Text('Admin login'),
                    ),
                  ),
                  if (_infoMessage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _infoMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.primary),
                    ),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _looksLikeEmail(String value) {
  final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  return regex.hasMatch(value.trim());
}

bool _looksLikePhoneE164(String value) {
  final normalized = value.trim();
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized);
}

bool _looksLikeOtpCode(String value) {
  final normalized = value.trim();
  return RegExp(r'^[0-9]{4,8}$').hasMatch(normalized);
}
