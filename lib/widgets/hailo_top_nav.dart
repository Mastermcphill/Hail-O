import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class HailoTopNav extends StatelessWidget {
  const HailoTopNav({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.onLeadingPressed,
    this.trailingIcon,
    this.onTrailingPressed,
    this.showBack = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final VoidCallback? onLeadingPressed;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingPressed;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _NavActionButton(
          icon: showBack
              ? Icons.arrow_back_rounded
              : (leadingIcon ?? Icons.person_outline_rounded),
          onPressed: showBack
              ? (onBack ?? () => Navigator.of(context).maybePop())
              : onLeadingPressed,
        ),
        const SizedBox(width: HailoSpacing.md),
        Expanded(
          child: Column(
            children: <Widget>[
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: HailoSpacing.md),
        _NavActionButton(
          icon: trailingIcon ?? Icons.notifications_none_rounded,
          onPressed: onTrailingPressed,
        ),
      ],
    );
  }
}

class _NavActionButton extends StatelessWidget {
  const _NavActionButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: HailoRadii.pill,
        border: Border.all(color: context.hailoTokens.outlineSoft),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: 'Navigation',
      ),
    );
  }
}
