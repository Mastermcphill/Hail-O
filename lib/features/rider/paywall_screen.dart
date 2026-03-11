import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../features/rideshare/models/ride_search_draft.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/trust_badge.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    this.offerPriceMinor,
    this.luggageCount,
    this.charterMode = false,
    this.draftEncoded,
  });

  final ApiClient apiClient;
  final String rideId;
  final int? offerPriceMinor;
  final int? luggageCount;
  final bool charterMode;
  final String? draftEncoded;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Timer? _timer;
  DateTime? _deadlineAtUtc;
  int _connectionFeeMinor = 0;
  Duration _remaining = Duration.zero;
  bool _isLoading = true;
  bool _isPaying = false;
  bool _expiredTriggered = false;
  String? _errorMessage;
  late final RideSearchDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = RideSearchDraft.fromEncoded(widget.draftEncoded);
    _openPaywall();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _openPaywall() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.apiClient.post(
        ApiPaths.ridePaywallOpen(widget.rideId),
        body: const <String, dynamic>{},
      );
      final deadlineAt = DateTime.tryParse(
        (response['deadline_at'] ?? '').toString(),
      )?.toUtc();
      final fee = (response['connection_fee_minor'] as num?)?.toInt() ?? 0;
      if (!mounted) {
        return;
      }
      setState(() {
        _deadlineAtUtc =
            deadlineAt ??
            DateTime.now().toUtc().add(const Duration(minutes: 10));
        _connectionFeeMinor = fee;
      });
      _startCountdown();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = formatApiError(error);
        _deadlineAtUtc = DateTime.now().toUtc().add(
          const Duration(minutes: 10),
        );
      });
      _startCountdown();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final deadline = _deadlineAtUtc;
    if (deadline == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final remaining = deadline.difference(now);
    if (!mounted) {
      return;
    }
    setState(() {
      _remaining = remaining.isNegative ? Duration.zero : remaining;
    });
    if (remaining <= Duration.zero && !_expiredTriggered) {
      _expiredTriggered = true;
      _handleExpiry();
    }
  }

  Future<void> _handleExpiry() async {
    try {
      await widget.apiClient.post(
        ApiPaths.rideCancel(widget.rideId),
        body: const <String, dynamic>{},
      );
    } catch (_) {
      // Ignore cancellation failures. The rider still needs to return to offers.
    }
    if (!mounted) {
      return;
    }
    context.go(
      '/rider/offers/${Uri.encodeComponent(widget.rideId)}?expired=true'
      '&draft=${Uri.encodeQueryComponent(_draft.toEncoded())}',
    );
  }

  Future<void> _pay() async {
    setState(() {
      _isPaying = true;
      _errorMessage = null;
    });
    try {
      await widget.apiClient.post(
        ApiPaths.ridePaywallPay(widget.rideId),
        body: const <String, dynamic>{},
      );
      if (!mounted) {
        return;
      }
      context.push(
        '/rider/seats/${Uri.encodeComponent(widget.rideId)}'
        '?charter_mode=${widget.charterMode}'
        '&draft=${Uri.encodeQueryComponent(_draft.toEncoded())}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = formatApiError(error);
      });
      _showSnackBar(formatApiError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deadlineLabel = _deadlineAtUtc == null
        ? '-'
        : DateFormat('EEE, MMM d • h:mm a').format(_deadlineAtUtc!.toLocal());
    final fareEstimateMinor =
        (widget.offerPriceMinor ??
        (_draft.baseFareMinor + _draft.premiumMarkupMinor));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PremiumPanel(
                gradient: context.hailoTokens.heroGradient,
                borderColor: Colors.white.withValues(alpha: 0.10),
                child: Wrap(
                  spacing: HailoSpacing.xl,
                  runSpacing: HailoSpacing.lg,
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PremiumPill(
                            label: 'Escrow Payment Protection',
                            icon: Icons.lock_clock_outlined,
                            backgroundColor: Color(0x24FFFFFF),
                            foregroundColor: Colors.white,
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          Text(
                            'Your payment is held securely until the journey begins.',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: HailoSpacing.md),
                          Text(
                            'Complete the connection fee to lock this protected booking, then choose your exact seat before confirmation.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          Wrap(
                            spacing: HailoSpacing.xs,
                            runSpacing: HailoSpacing.xs,
                            children: const <Widget>[
                              TrustBadge(
                                label: 'Protected booking',
                                icon: Icons.shield_outlined,
                                tint: Colors.white,
                              ),
                              TrustBadge(
                                label: 'Seat choice next',
                                icon: Icons.event_seat_outlined,
                                tint: Colors.white,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: PremiumPanel(
                        padding: const EdgeInsets.all(HailoSpacing.md),
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.12),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                        ),
                        borderColor: Colors.white.withValues(alpha: 0.12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _PaywallRow(
                              label: 'Ride',
                              value: _draft.bookingSummaryLabel,
                              inverse: true,
                            ),
                            const SizedBox(height: HailoSpacing.xs),
                            _PaywallRow(
                              label: 'Fare estimate',
                              value: _money(fareEstimateMinor),
                              inverse: true,
                            ),
                            const SizedBox(height: HailoSpacing.xs),
                            _PaywallRow(
                              label: 'Connection fee',
                              value: _money(_connectionFeeMinor),
                              inverse: true,
                            ),
                            const SizedBox(height: HailoSpacing.xs),
                            _PaywallRow(
                              label: 'Pay by',
                              value: deadlineLabel,
                              inverse: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HailoSpacing.section),
              Wrap(
                spacing: HailoSpacing.md,
                runSpacing: HailoSpacing.md,
                children: <Widget>[
                  SizedBox(
                    width: 460,
                    child: PremiumPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PremiumSectionHeader(
                            eyebrow: 'Booking summary',
                            title: 'Review the booking before you continue.',
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          _PaywallRow(label: 'Ride ID', value: widget.rideId),
                          const SizedBox(height: HailoSpacing.sm),
                          _PaywallRow(
                            label: 'Travel mode',
                            value: _draft.travelModeLabel,
                          ),
                          const SizedBox(height: HailoSpacing.sm),
                          _PaywallRow(
                            label: 'Seat tier',
                            value: _draft.seatTierLabel,
                          ),
                          const SizedBox(height: HailoSpacing.sm),
                          _PaywallRow(
                            label: 'Departure',
                            value: DateFormat(
                              'EEE, MMM d • h:mm a',
                            ).format(_draft.departureAt.toLocal()),
                          ),
                          const SizedBox(height: HailoSpacing.sm),
                          _PaywallRow(
                            label: 'Passengers',
                            value: '${_draft.passengerCount}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 460,
                    child: PremiumPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PremiumSectionHeader(
                            eyebrow: 'Time-sensitive',
                            title:
                                'This match is held briefly while you confirm.',
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          _PaywallRow(
                            label: 'Time left',
                            value: _formatDuration(_remaining),
                          ),
                          const SizedBox(height: HailoSpacing.sm),
                          _PaywallRow(
                            label: 'Connection fee',
                            value: _money(_connectionFeeMinor),
                          ),
                          const SizedBox(height: HailoSpacing.sm),
                          _PaywallRow(
                            label: 'Luggage',
                            value:
                                '${widget.luggageCount ?? _draft.luggageCount}',
                          ),
                          if (_isLoading) ...<Widget>[
                            const SizedBox(height: HailoSpacing.md),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: HailoSpacing.md),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: HailoSpacing.section),
              FilledButton(
                key: const Key('paywall_continue_button'),
                onPressed:
                    (_isLoading || _remaining == Duration.zero || _isPaying)
                    ? null
                    : _pay,
                child: _isPaying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm protected booking'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _PaywallRow extends StatelessWidget {
  const _PaywallRow({
    required this.label,
    required this.value,
    this.inverse = false,
  });

  final String label;
  final String value;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final labelColor = inverse
        ? Colors.white.withValues(alpha: 0.76)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final valueColor = inverse
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 136,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: labelColor),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

String _money(int amountMinor) {
  return '\$${(amountMinor / 100).toStringAsFixed(2)}';
}
