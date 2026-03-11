import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/role_routes.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/premium_ui.dart';
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

  PublicAccountRole _accountRole = PublicAccountRole.rider;
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

  bool get _supportsOtp => _accountRole == PublicAccountRole.rider;

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

  void _switchAccountRole(PublicAccountRole role) {
    if (_accountRole == role) {
      return;
    }
    setState(() {
      _accountRole = role;
      _errorMessage = null;
      _infoMessage = null;
      _otpRequested = false;
      if (!_supportsOtp) {
        _mode = _AuthMode.email;
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
        _infoMessage = 'Verification code sent. Enter it below to continue.';
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
        _errorMessage = 'Enter the OTP code we sent to your number.';
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: _mode == _AuthMode.otp
            ? (_otpRequested ? 'Verifying your code...' : 'Requesting code...')
            : 'Signing you in...',
        child: AuthExperienceFrame(
          eyebrow: 'Hail-O Rideshare',
          title: 'Sign in to book, drive, or operate your fleet.',
          description:
              'Continue as Passenger, Driver, or Fleet Operator. Passenger booking stays fast with OTP while operator workspaces stay role-correct and private.',
          highlights: const <String>[
            'Book premium rides across cities, states, and borders.',
            'Escrow payment protection stays visible through the booking flow.',
            'Role-aware routing keeps each workspace focused and private.',
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go(landingPath),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                ),
              ),
              const SizedBox(height: HailoSpacing.xs),
              PremiumSectionHeader(
                eyebrow: 'Sign in',
                title: 'Continue in the right role',
                description: _roleDescription(_accountRole),
              ),
              const SizedBox(height: HailoSpacing.md),
              Wrap(
                spacing: HailoSpacing.sm,
                runSpacing: HailoSpacing.sm,
                children: PublicAccountRole.values
                    .map((role) {
                      final selected = _accountRole == role;
                      return ChoiceChip(
                        label: Text(labelForPublicAccount(role)),
                        selected: selected,
                        onSelected: (_) => _switchAccountRole(role),
                        avatar: Icon(_iconForRole(role), size: 16),
                      );
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: HailoSpacing.md),
              if (_supportsOtp) ...<Widget>[
                SegmentedButton<_AuthMode>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<_AuthMode>>[
                    ButtonSegment<_AuthMode>(
                      value: _AuthMode.otp,
                      icon: Icon(Icons.sms_outlined),
                      label: Text('Phone OTP'),
                    ),
                    ButtonSegment<_AuthMode>(
                      value: _AuthMode.email,
                      icon: Icon(Icons.alternate_email_rounded),
                      label: Text('Email'),
                    ),
                  ],
                  selected: <_AuthMode>{_mode},
                  onSelectionChanged: (selection) =>
                      _switchMode(selection.first),
                ),
                const SizedBox(height: HailoSpacing.md),
              ],
              if (_mode == _AuthMode.email || !_supportsOtp) ...<Widget>[
                Form(
                  key: _emailFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const <String>[AutofillHints.username],
                        validator: (value) {
                          final email = (value ?? '').trim();
                          if (email.isEmpty) {
                            return 'Email is required';
                          }
                          if (!_looksLikeEmail(email)) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: _accountRole == PublicAccountRole.rider
                              ? 'Email'
                              : 'Work email',
                          hintText: _accountRole == PublicAccountRole.fleetOwner
                              ? 'operations@yourfleet.com'
                              : 'name@example.com',
                        ),
                      ),
                      const SizedBox(height: HailoSpacing.md),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const <String>[AutofillHints.password],
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
                          hintText: 'Enter your secure password',
                        ),
                      ),
                      const SizedBox(height: HailoSpacing.md),
                      PremiumPill(
                        label:
                            'We will route you to the correct workspace automatically.',
                        icon: Icons.verified_user_outlined,
                      ),
                      const SizedBox(height: HailoSpacing.lg),
                      FilledButton(
                        onPressed: _isLoading ? null : _loginWithEmail,
                        child: Text(_emailButtonLabel(_accountRole)),
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
                    labelText: 'Phone number',
                    hintText: '+2348012345678',
                  ),
                ),
                const SizedBox(height: HailoSpacing.sm),
                PremiumPill(
                  label:
                      'Passenger OTP is built for quick, secure access on the move.',
                  icon: Icons.flash_on_rounded,
                ),
                if (_otpRequested) ...<Widget>[
                  const SizedBox(height: HailoSpacing.md),
                  TextField(
                    controller: _otpCodeController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _isLoading ? null : _verifyOtp(),
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      hintText: 'Enter the code you received',
                    ),
                  ),
                  const SizedBox(height: HailoSpacing.lg),
                  FilledButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    child: const Text('Verify and continue'),
                  ),
                  const SizedBox(height: HailoSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _isLoading ? null : _requestOtp,
                      child: const Text('Send a fresh code'),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: HailoSpacing.lg),
                  FilledButton(
                    onPressed: _isLoading ? null : _requestOtp,
                    child: const Text('Send verification code'),
                  ),
                ],
              ],
              const SizedBox(height: HailoSpacing.md),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => context.go(
                        registrationPathForPublicAccount(_accountRole),
                      ),
                child: Text(_registrationLabel(_accountRole)),
              ),
              if (_infoMessage != null) ...<Widget>[
                const SizedBox(height: HailoSpacing.xs),
                Text(
                  _infoMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: HailoSpacing.xs),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _roleDescription(PublicAccountRole role) {
  switch (role) {
    case PublicAccountRole.driver:
      return 'Driver access for online status, assigned trips, earnings, and compliance.';
    case PublicAccountRole.fleetOwner:
      return 'Fleet Operator access for vehicles, drivers, route operations, and settlement oversight.';
    case PublicAccountRole.rider:
      return 'Passenger access for booking rides, choosing seats, and tracking protected trips.';
  }
}

String _emailButtonLabel(PublicAccountRole role) {
  switch (role) {
    case PublicAccountRole.driver:
      return 'Enter driver workspace';
    case PublicAccountRole.fleetOwner:
      return 'Enter fleet operator workspace';
    case PublicAccountRole.rider:
      return 'Sign in';
  }
}

String _registrationLabel(PublicAccountRole role) {
  switch (role) {
    case PublicAccountRole.driver:
      return 'Need an operator account? Become a driver';
    case PublicAccountRole.fleetOwner:
      return 'Need an operator account? Register your fleet';
    case PublicAccountRole.rider:
      return 'New to HAIL-O? Create a passenger account';
  }
}

IconData _iconForRole(PublicAccountRole role) {
  switch (role) {
    case PublicAccountRole.driver:
      return Icons.local_taxi_outlined;
    case PublicAccountRole.fleetOwner:
      return Icons.directions_bus_rounded;
    case PublicAccountRole.rider:
      return Icons.person_outline_rounded;
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
