import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../features/rideshare/models/ride_search_draft.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/seat_layout_widget.dart';
import '../../widgets/trust_badge.dart';

class SeatSelectionScreen extends StatefulWidget {
  const SeatSelectionScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    this.offerPriceMinor,
    this.charterMode = false,
    this.draftEncoded,
  });

  final ApiClient apiClient;
  final String rideId;
  final int? offerPriceMinor;
  final bool charterMode;
  final String? draftEncoded;

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  List<SeatVisualSpec> _seatSpecs = <SeatVisualSpec>[];
  Set<String> _selectedSeatIds = <String>{};
  int _basePriceMinor = 0;
  int _dailyRateMinor = 0;
  bool _charterMode = false;
  late final RideSearchDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = RideSearchDraft.fromEncoded(widget.draftEncoded);
    _charterMode = widget.charterMode;
    _loadSeats();
  }

  Future<void> _loadSeats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.apiClient.get(
        ApiPaths.rideSeats(widget.rideId),
      );
      final seats = (response['seats'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          )
          .toList(growable: false);

      final parsedSpecs = seats.isEmpty
          ? _fallbackSeatSpecs()
          : seats.map(_specFromApiSeat).toList(growable: false);
      final initiallySelected = parsedSpecs
          .where(
            (seat) =>
                seat.available && seat.seatId == 'FRONT_RIGHT' && _charterMode,
          )
          .map((seat) => seat.seatId)
          .toSet();

      if (!mounted) {
        return;
      }
      setState(() {
        _seatSpecs = parsedSpecs;
        _selectedSeatIds = initiallySelected;
        _basePriceMinor =
            (response['base_price_minor'] as num?)?.toInt() ?? 7000;
        _dailyRateMinor = (response['daily_rate_minor'] as num?)?.toInt() ?? 0;
        _charterMode = response['charter_mode'] == true || widget.charterMode;
      });
      if (_charterMode) {
        _applyCharterAutoSelect();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _seatSpecs = _fallbackSeatSpecs();
        _basePriceMinor = 7000;
        _dailyRateMinor = 0;
        _errorMessage = formatApiError(error);
      });
      if (_charterMode) {
        _applyCharterAutoSelect();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyCharterAutoSelect() {
    setState(() {
      _selectedSeatIds = _seatSpecs
          .where((seat) => seat.available)
          .map((seat) => seat.seatId)
          .toSet();
    });
  }

  void _toggleSeat(String seatId) {
    if (_charterMode) {
      return;
    }
    setState(() {
      if (_selectedSeatIds.contains(seatId)) {
        _selectedSeatIds.remove(seatId);
      } else {
        _selectedSeatIds.add(seatId);
      }
    });
  }

  Future<void> _confirm() async {
    if (_selectedSeatIds.isEmpty) {
      _showSnackBar('Select at least one seat.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final pricingMinor = _computePricingMinor();
      final response = await widget.apiClient.post(
        ApiPaths.rideSeatsSelect(widget.rideId),
        body: <String, dynamic>{
          'seat_ids': _selectedSeatIds.toList(growable: false),
          'pricing_minor': pricingMinor,
        },
      );
      if (!mounted) {
        return;
      }
      final purchaseId = _extractPurchaseId(response);
      context.push(
        '/rider/timeline/${Uri.encodeComponent(purchaseId)}'
        '?rideId=${Uri.encodeQueryComponent(widget.rideId)}',
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
          _isSubmitting = false;
        });
      }
    }
  }

  int _computePricingMinor() {
    if (_charterMode) {
      if (_dailyRateMinor > 0) {
        return _dailyRateMinor;
      }
      return _seatSpecs.fold<int>(0, (sum, seat) => sum + seat.totalPriceMinor);
    }
    return _seatSpecs
        .where((seat) => _selectedSeatIds.contains(seat.seatId))
        .fold<int>(0, (sum, seat) => sum + seat.totalPriceMinor);
  }

  @override
  Widget build(BuildContext context) {
    final pricingMinor = _computePricingMinor();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
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
                            label: 'Seat selection',
                            icon: Icons.event_seat_outlined,
                            backgroundColor: Color(0x24FFFFFF),
                            foregroundColor: Colors.white,
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          Text(
                            'Choose your exact seat before you lock the journey.',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: HailoSpacing.md),
                          Text(
                            'Seat upgrades, window preference, front-row comfort, and executive placement are surfaced directly in the seat map.',
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
                                label: 'Window options',
                                icon: Icons
                                    .airline_seat_individual_suite_outlined,
                                tint: Colors.white,
                              ),
                              TrustBadge(
                                label: 'Extra legroom',
                                icon: Icons.airline_seat_legroom_extra_outlined,
                                tint: Colors.white,
                              ),
                              TrustBadge(
                                label: 'Executive seats',
                                icon: Icons.workspace_premium_outlined,
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
                            _SeatSummaryLine(
                              label: 'Ride',
                              value: _draft.bookingSummaryLabel,
                              inverse: true,
                            ),
                            const SizedBox(height: HailoSpacing.xs),
                            _SeatSummaryLine(
                              label: 'Selected seats',
                              value: '${_selectedSeatIds.length}',
                              inverse: true,
                            ),
                            const SizedBox(height: HailoSpacing.xs),
                            _SeatSummaryLine(
                              label: 'Seat total',
                              value: _money(pricingMinor),
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
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: HailoSpacing.section),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SeatLayoutWidget(
                  seats: _seatSpecs,
                  selectedSeatIds: _selectedSeatIds,
                  onToggleSeat: _toggleSeat,
                  charterMode: _charterMode,
                ),
              const SizedBox(height: HailoSpacing.lg),
              Wrap(
                spacing: HailoSpacing.md,
                runSpacing: HailoSpacing.md,
                children: <Widget>[
                  SizedBox(
                    width: 520,
                    child: PremiumPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PremiumSectionHeader(
                            eyebrow: 'Pricing summary',
                            title: 'Clear seat pricing without surprise math.',
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          _SeatSummaryLine(
                            label: 'Base fare',
                            value: _money(_basePriceMinor),
                          ),
                          const SizedBox(height: HailoSpacing.sm),
                          _SeatSummaryLine(
                            label: _charterMode
                                ? 'Charter daily rate'
                                : 'Seat total',
                            value: _money(pricingMinor),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 520,
                    child: PremiumPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const <Widget>[
                          PremiumSectionHeader(
                            eyebrow: 'Escrow note',
                            title:
                                'Payment protection remains active after seat selection.',
                            description:
                                'Your protected booking stays tied to the journey timeline from seat confirmation through departure.',
                          ),
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
                key: const Key('confirm_seats_button'),
                onPressed: (_isLoading || _isSubmitting) ? null : _confirm,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm seats'),
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
}

SeatVisualSpec _specFromApiSeat(Map<String, dynamic> seat) {
  final seatId = (seat['seat_id'] ?? seat['seat_code'] ?? '')
      .toString()
      .toUpperCase();
  final seatType = (seat['seat_type'] ?? '').toString().toLowerCase();
  final tags = <String>[
    if (seatId == 'FRONT_RIGHT') 'Front row',
    if (seatId == 'FRONT_RIGHT' ||
        seatId == 'BACK_LEFT' ||
        seatId == 'BACK_RIGHT')
      'Window',
    if (seatId == 'FRONT_RIGHT') 'Extra legroom',
    if (seatId == 'BACK_MIDDLE') 'Quieter seat',
  ];
  return SeatVisualSpec(
    seatId: seatId,
    label: _labelForSeat(seatId),
    available: seat['available'] != false,
    basePriceMinor: (seat['base_fare_minor'] as num?)?.toInt() ?? 7000,
    markupMinor: (seat['markup_minor'] as num?)?.toInt() ?? 0,
    seatClass: _seatClassForSeat(seatId, seatType),
    tags: tags.isEmpty ? const <String>['Available'] : tags,
  );
}

List<SeatVisualSpec> _fallbackSeatSpecs() {
  return <SeatVisualSpec>[
    const SeatVisualSpec(
      seatId: 'FRONT_RIGHT',
      label: 'Front right',
      available: true,
      basePriceMinor: 7000,
      markupMinor: 1800,
      seatClass: 'Executive',
      tags: <String>['Front row', 'Window', 'Extra legroom'],
    ),
    const SeatVisualSpec(
      seatId: 'BACK_LEFT',
      label: 'Back left',
      available: true,
      basePriceMinor: 7000,
      markupMinor: 900,
      seatClass: 'Comfort',
      tags: <String>['Window'],
    ),
    const SeatVisualSpec(
      seatId: 'BACK_MIDDLE',
      label: 'Back middle',
      available: true,
      basePriceMinor: 7000,
      markupMinor: 0,
      seatClass: 'Standard',
      tags: <String>['Quieter seat'],
    ),
    const SeatVisualSpec(
      seatId: 'BACK_RIGHT',
      label: 'Back right',
      available: true,
      basePriceMinor: 7000,
      markupMinor: 1400,
      seatClass: 'Premium',
      tags: <String>['Window'],
    ),
  ];
}

String _labelForSeat(String seatId) {
  switch (seatId) {
    case 'FRONT_RIGHT':
      return 'Front right';
    case 'BACK_LEFT':
      return 'Back left';
    case 'BACK_MIDDLE':
      return 'Back middle';
    case 'BACK_RIGHT':
      return 'Back right';
    default:
      return seatId.replaceAll('_', ' ').toLowerCase();
  }
}

String _seatClassForSeat(String seatId, String seatType) {
  if (seatType.contains('executive') || seatId == 'FRONT_RIGHT') {
    return 'Executive';
  }
  if (seatType.contains('premium') || seatId == 'BACK_RIGHT') {
    return 'Premium';
  }
  if (seatType.contains('comfort') || seatId == 'BACK_LEFT') {
    return 'Comfort';
  }
  return 'Standard';
}

String _extractPurchaseId(Map<String, dynamic> response) {
  final direct = response['purchase_id']?.toString() ?? '';
  if (direct.trim().isNotEmpty) {
    return direct.trim();
  }
  final purchase = response['purchase'];
  if (purchase is Map) {
    final nested = purchase['id']?.toString() ?? '';
    if (nested.trim().isNotEmpty) {
      return nested.trim();
    }
  }
  return 'purchase_fallback';
}

class _SeatSummaryLine extends StatelessWidget {
  const _SeatSummaryLine({
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
          width: 130,
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
