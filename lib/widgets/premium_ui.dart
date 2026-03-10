import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({
    super.key,
    required this.child,
    this.topGlowAlignment = Alignment.topRight,
  });

  final Widget child;
  final Alignment topGlowAlignment;

  @override
  Widget build(BuildContext context) {
    final tokens = context.hailoTokens;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: tokens.pageGradient),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            right: -40,
            child: _GlowOrb(
              size: 260,
              color: tokens.glow.withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            top: 120,
            left: -80,
            child: _GlowOrb(
              size: 220,
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.10),
            ),
          ),
          Positioned(
            bottom: -70,
            right: -20,
            child: _GlowOrb(
              size: 200,
              color: tokens.canvasStrong.withValues(alpha: 0.80),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class PremiumPanel extends StatelessWidget {
  const PremiumPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HailoSpacing.lg),
    this.borderRadius = HailoRadii.lg,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.hailoTokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient ?? tokens.panelGradient,
        borderRadius: borderRadius,
        border: Border.all(
          color: borderColor ?? tokens.outlineSoft.withValues(alpha: 0.72),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            blurRadius: 30,
            offset: const Offset(0, 16),
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class PremiumSectionHeader extends StatelessWidget {
  const PremiumSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                eyebrow.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: HailoSpacing.xs),
              Text(title, style: theme.textTheme.headlineSmall),
              if (description != null) ...<Widget>[
                const SizedBox(height: HailoSpacing.xs),
                Text(
                  description!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: HailoSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

class PremiumPill extends StatelessWidget {
  const PremiumPill({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedBackground =
        backgroundColor ?? theme.colorScheme.primary.withValues(alpha: 0.10);
    final resolvedForeground = foregroundColor ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: HailoSpacing.sm,
        vertical: HailoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: HailoRadii.pill,
      ),
      child: Wrap(
        spacing: HailoSpacing.xs,
        runSpacing: HailoSpacing.xxs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          if (icon != null) Icon(icon, size: 14, color: resolvedForeground),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: resolvedForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumMetricTile extends StatelessWidget {
  const PremiumMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.footnote,
    this.icon,
    this.tint,
  });

  final String label;
  final String value;
  final String? footnote;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedTint = tint ?? colorScheme.primary;
    return PremiumPanel(
      padding: const EdgeInsets.all(HailoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: resolvedTint.withValues(alpha: 0.12),
                borderRadius: HailoRadii.sm,
              ),
              child: Icon(icon, color: resolvedTint),
            ),
            const SizedBox(height: HailoSpacing.md),
          ],
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: HailoSpacing.xs),
          Text(value, style: theme.textTheme.headlineSmall),
          if (footnote != null) ...<Widget>[
            const SizedBox(height: HailoSpacing.xs),
            Text(
              footnote!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PremiumActionCard extends StatelessWidget {
  const PremiumActionCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.onTap,
    this.trailingLabel,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: HailoRadii.md,
      onTap: onTap,
      child: PremiumPanel(
        padding: const EdgeInsets.all(HailoSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: HailoRadii.sm,
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: HailoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: HailoSpacing.xs),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HailoSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (trailingLabel != null)
                  Text(
                    trailingLabel!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: HailoSpacing.xs),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PremiumListItem extends StatelessWidget {
  const PremiumListItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData leadingIcon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(HailoSpacing.md),
      decoration: BoxDecoration(
        color: context.hailoTokens.surfaceSecondary,
        borderRadius: HailoRadii.md,
        border: Border.all(color: context.hailoTokens.outlineSoft),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: HailoRadii.sm,
            ),
            child: Icon(leadingIcon, color: colorScheme.primary),
          ),
          const SizedBox(width: HailoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: HailoSpacing.xxs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: HailoSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class AuthExperienceFrame extends StatelessWidget {
  const AuthExperienceFrame({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.highlights,
    required this.child,
    this.footer,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<String> highlights;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BrandBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              HailoSpacing.lg,
              HailoSpacing.md,
              HailoSpacing.lg,
              HailoSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Wrap(
                spacing: HailoSpacing.lg,
                runSpacing: HailoSpacing.lg,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: PremiumPanel(
                      gradient: context.hailoTokens.heroGradient,
                      borderColor: Colors.white.withValues(alpha: 0.12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          PremiumPill(
                            label: eyebrow,
                            icon: Icons.auto_awesome_rounded,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.10,
                            ),
                            foregroundColor: Colors.white,
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          SizedBox(
                            height: 54,
                            child: Image.asset(
                              'assets/brand/logo_lockup.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.local_taxi_rounded,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                            ),
                          ),
                          const SizedBox(height: HailoSpacing.xl),
                          Text(
                            title,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: HailoSpacing.md),
                          Text(
                            description,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.88),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: HailoSpacing.section),
                          for (final highlight in highlights) ...<Widget>[
                            _AuthHighlightRow(label: highlight),
                            const SizedBox(height: HailoSpacing.sm),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      children: <Widget>[
                        PremiumPanel(child: child),
                        if (footer != null) ...<Widget>[
                          const SizedBox(height: HailoSpacing.md),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthHighlightRow extends StatelessWidget {
  const _AuthHighlightRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: HailoRadii.sm,
          ),
          child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: HailoSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: color, blurRadius: 80, spreadRadius: 12),
          ],
        ),
      ),
    );
  }
}
