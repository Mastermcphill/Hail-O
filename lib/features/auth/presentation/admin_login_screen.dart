import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/role_routes.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/loading_overlay.dart';
import '../../../widgets/premium_ui.dart';
import '../data/auth_api.dart';
import '../session/auth_session.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, this.nextPath});

  final String? nextPath;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authSession = context.read<AuthSession>();
      final session = await authSession.login(
        _emailController.text.trim(),
        _passwordController.text,
        requireAdmin: true,
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
        if (error is AuthSessionException) {
          _errorMessage = error.message;
        } else {
          _errorMessage = mapLoginErrorMessage(error);
        }
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
      backgroundColor: Colors.transparent,
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: 'Authenticating internal access...',
        child: AuthExperienceFrame(
          eyebrow: 'Internal access',
          title: 'Restricted HAIL-O operations entry.',
          description:
              'This route is reserved for internal operators and is intentionally excluded from the public product experience.',
          highlights: const <String>[
            'Admin access is hidden from all public landing and onboarding surfaces.',
            'Non-admin accounts are blocked from mutating session state through this route.',
            'Use only for authorized internal operations and protected deep links.',
          ],
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go(landingPath),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Return to public app'),
                  ),
                ),
                const SizedBox(height: HailoSpacing.xs),
                const PremiumSectionHeader(
                  eyebrow: 'Admin authentication',
                  title: 'Verify internal credentials',
                  description:
                      'Only authorized HAIL-O operators should continue beyond this point.',
                ),
                const SizedBox(height: HailoSpacing.md),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
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
                  decoration: const InputDecoration(
                    labelText: 'Internal email',
                    hintText: 'operator@hailo.internal',
                  ),
                ),
                const SizedBox(height: HailoSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _isLoading ? null : _login(),
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Password is required';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your internal password',
                  ),
                ),
                const SizedBox(height: HailoSpacing.md),
                PremiumPill(
                  label:
                      'Hidden route. Public users should never see this entry.',
                  icon: Icons.lock_outline_rounded,
                  backgroundColor: colorScheme.error.withValues(alpha: 0.10),
                  foregroundColor: colorScheme.error,
                ),
                const SizedBox(height: HailoSpacing.lg),
                FilledButton(
                  onPressed: _isLoading ? null : _login,
                  child: const Text('Continue to internal workspace'),
                ),
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: HailoSpacing.sm),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
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
