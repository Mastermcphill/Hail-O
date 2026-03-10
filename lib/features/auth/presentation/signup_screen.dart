import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/role_routes.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/loading_overlay.dart';
import '../../../widgets/premium_ui.dart';
import '../data/auth_api.dart';
import '../session/auth_session.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({
    super.key,
    this.nextPath,
    this.accountRole = PublicAccountRole.rider,
  });

  final String? nextPath;
  final PublicAccountRole accountRole;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _nameController.text.trim();

    try {
      final authSession = context.read<AuthSession>();
      final session = await authSession.register(
        email: email,
        password: password,
        role: backendRoleForPublicAccount(widget.accountRole),
        displayName: displayName,
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
        _errorMessage = mapRegisterErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _SignupCopy.forRole(widget.accountRole);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LoadingOverlay(
        isLoading: _isSubmitting,
        message: config.loadingMessage,
        child: AuthExperienceFrame(
          eyebrow: config.eyebrow,
          title: config.heroTitle,
          description: config.heroDescription,
          highlights: config.highlights,
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
                    label: const Text('Back'),
                  ),
                ),
                const SizedBox(height: HailoSpacing.xs),
                PremiumSectionHeader(
                  eyebrow: config.formEyebrow,
                  title: config.formTitle,
                  description: config.formDescription,
                ),
                const SizedBox(height: HailoSpacing.md),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.name],
                  validator: (value) {
                    final trimmed = (value ?? '').trim();
                    if (trimmed.isEmpty) {
                      return config.nameError;
                    }
                    if (trimmed.length < 3) {
                      return config.nameLengthError;
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: config.nameLabel,
                    hintText: config.nameHint,
                  ),
                ),
                const SizedBox(height: HailoSpacing.md),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.newUsername],
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
                    labelText: config.emailLabel,
                    hintText: config.emailHint,
                  ),
                ),
                const SizedBox(height: HailoSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.newPassword],
                  validator: (value) {
                    final password = value ?? '';
                    if (password.isEmpty) {
                      return 'Password is required';
                    }
                    if (password.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    hintText: 'Create a strong password',
                  ),
                ),
                const SizedBox(height: HailoSpacing.md),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
                  validator: (value) {
                    final confirmPassword = value ?? '';
                    if (confirmPassword.isEmpty) {
                      return 'Confirm your password';
                    }
                    if (confirmPassword != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    hintText: 'Re-enter the same password',
                  ),
                ),
                const SizedBox(height: HailoSpacing.md),
                PremiumPill(
                  label: config.trustNote,
                  icon: Icons.shield_outlined,
                ),
                const SizedBox(height: HailoSpacing.lg),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: Text(config.primaryCta),
                ),
                const SizedBox(height: HailoSpacing.xs),
                TextButton(
                  onPressed: _isSubmitting ? null : () => context.go(loginPath),
                  child: Text(config.secondaryCta),
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

class _SignupCopy {
  const _SignupCopy({
    required this.eyebrow,
    required this.heroTitle,
    required this.heroDescription,
    required this.highlights,
    required this.formEyebrow,
    required this.formTitle,
    required this.formDescription,
    required this.nameLabel,
    required this.nameHint,
    required this.nameError,
    required this.nameLengthError,
    required this.emailLabel,
    required this.emailHint,
    required this.trustNote,
    required this.primaryCta,
    required this.secondaryCta,
    required this.loadingMessage,
  });

  final String eyebrow;
  final String heroTitle;
  final String heroDescription;
  final List<String> highlights;
  final String formEyebrow;
  final String formTitle;
  final String formDescription;
  final String nameLabel;
  final String nameHint;
  final String nameError;
  final String nameLengthError;
  final String emailLabel;
  final String emailHint;
  final String trustNote;
  final String primaryCta;
  final String secondaryCta;
  final String loadingMessage;

  static _SignupCopy forRole(PublicAccountRole role) {
    switch (role) {
      case PublicAccountRole.driver:
        return const _SignupCopy(
          eyebrow: 'Driver onboarding',
          heroTitle: 'Step into the HAIL-O operator network.',
          heroDescription:
              'Create your driver account to receive trip opportunities, monitor performance, manage compliance, and access your earnings workspace.',
          highlights: <String>[
            'Purpose-built driver dashboard for trip flow, performance, and support.',
            'Seamless progression into vehicle and compliance setup after account creation.',
            'Premium operator UX without exposing any admin or internal tooling.',
          ],
          formEyebrow: 'Become a driver',
          formTitle: 'Create your operator profile',
          formDescription:
              'Use a work-ready identity. You will complete licensing, vehicle, and compliance details after this secure account step.',
          nameLabel: 'Full name',
          nameHint: 'e.g. Ayo McPhill',
          nameError: 'Full name is required',
          nameLengthError: 'Enter your full name',
          emailLabel: 'Work email',
          emailHint: 'driver@hailo.com',
          trustNote:
              'Your account opens the driver workspace; compliance verification follows inside the app.',
          primaryCta: 'Create driver account',
          secondaryCta: 'Already approved? Sign in',
          loadingMessage: 'Creating your driver account...',
        );
      case PublicAccountRole.fleetOwner:
        return const _SignupCopy(
          eyebrow: 'Fleet registration',
          heroTitle: 'Launch a premium fleet command center.',
          heroDescription:
              'Register your fleet organization to manage vehicles, drivers, dispatch visibility, settlements, and compliance from one elevated workspace.',
          highlights: <String>[
            'Role-correct fleet workspace for operations, vehicles, and earnings oversight.',
            'Built to scale from a few vehicles to a modern multi-city transport operation.',
            'Conversion-ready registration flow with no public admin clutter.',
          ],
          formEyebrow: 'Register fleet',
          formTitle: 'Create your fleet organization account',
          formDescription:
              'Start with the account layer first. Vehicle rosters, driver assignments, and compliance details are completed after sign-up.',
          nameLabel: 'Fleet or company name',
          nameHint: 'e.g. HAIL-O Executive Roadlines',
          nameError: 'Fleet name is required',
          nameLengthError: 'Enter your organization name',
          emailLabel: 'Operations email',
          emailHint: 'ops@yourfleet.com',
          trustNote:
              'This step creates your fleet owner workspace and unlocks the operations dashboard.',
          primaryCta: 'Register fleet',
          secondaryCta: 'Already operating with us? Sign in',
          loadingMessage: 'Registering your fleet...',
        );
      case PublicAccountRole.rider:
        return const _SignupCopy(
          eyebrow: 'Passenger account',
          heroTitle: 'Join the flagship road-travel network.',
          heroDescription:
              'Create your passenger account for within-city, inter-city, inter-state, and cross-border road journeys with premium safety cues and elegant booking flow.',
          highlights: <String>[
            'Fast entry into booking, trip history, support, and profile tools.',
            'Designed for first-time riders without sacrificing a premium look and feel.',
            'Trust-led experience with clear pricing, support, and travel mode guidance.',
          ],
          formEyebrow: 'Create account',
          formTitle: 'Open your passenger account',
          formDescription:
              'Use the identity you want associated with your road-travel profile. You can complete other personal details after sign-up.',
          nameLabel: 'Full name',
          nameHint: 'e.g. Ada Nwafor',
          nameError: 'Full name is required',
          nameLengthError: 'Enter your full name',
          emailLabel: 'Email',
          emailHint: 'traveler@example.com',
          trustNote:
              'Your account is created securely and routed into the rider experience immediately after sign-up.',
          primaryCta: 'Create passenger account',
          secondaryCta: 'Already have an account? Sign in',
          loadingMessage: 'Creating your account...',
        );
    }
  }
}

bool _looksLikeEmail(String value) {
  final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  return regex.hasMatch(value.trim());
}
