import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    this.offerPriceMinor,
    this.luggageCount,
    this.charterMode = false,
  });

  final ApiClient apiClient;
  final String rideId;
  final int? offerPriceMinor;
  final int? luggageCount;
  final bool charterMode;

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

  @override
  void initState() {
    super.initState();
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
      // Ignore cancel failure; we still route back with expired state.
    }
    if (!mounted) {
      return;
    }
    context.go(
      '/rider/offers/${Uri.encodeComponent(widget.rideId)}?expired=true',
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
        '?charter_mode=${widget.charterMode}',
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
        : DateFormat('yyyy-MM-dd HH:mm:ss').format(_deadlineAtUtc!.toLocal());
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Connection Fee Paywall',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  SelectableText('ride_id: ${widget.rideId}'),
                  const SizedBox(height: 14),
                  _InfoRow(
                    label: 'connection_fee_minor',
                    value: _connectionFeeMinor.toString(),
                  ),
                  _InfoRow(label: 'deadline_at', value: deadlineLabel),
                  _InfoRow(
                    label: 'time_left',
                    value: _formatDuration(_remaining),
                  ),
                  if (_isLoading) ...<Widget>[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                  if (_errorMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
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
                        : const Text('Pay Connection Fee'),
                  ),
                ],
              ),
            ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(width: 170, child: Text(label)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
