import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/api/mock_backend_store.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    required this.offerPriceMinor,
    required this.charterMode,
    required this.luggageCount,
  });

  final ApiClient apiClient;
  final String rideId;
  final int offerPriceMinor;
  final bool charterMode;
  final int luggageCount;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  Timer? _timer;
  DateTime? _deadlineAt;
  int _connectionFeeMinor = 0;
  Duration _remaining = Duration.zero;
  bool _isLoading = true;
  bool _isPaying = false;
  bool _isExpiredHandling = false;
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
      _applyPaywallResponse(response);
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        _applyPaywallResponse(_mockPaywallResponse(widget.rideId));
      } else {
        _errorMessage = formatApiError(error);
        _applyPaywallResponse(_mockPaywallResponse(widget.rideId));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyPaywallResponse(Map<String, dynamic> response) {
    final fee = _readInt(
      response['connection_fee_minor'] ?? response['fee_minor'] ?? 0,
    );
    final deadlineRaw = _readString(response['deadline_at']);
    final fallbackDeadline = DateTime.now().toUtc().add(
      const Duration(minutes: 10),
    );
    final deadline =
        DateTime.tryParse(deadlineRaw)?.toUtc() ?? fallbackDeadline;
    MockBackendStore.paywallByRideId[widget.rideId] = <String, dynamic>{
      'connection_fee_minor': fee,
      'deadline_at': deadline.toIso8601String(),
    };
    _deadlineAt = deadline;
    _connectionFeeMinor = fee;
    _tickCountdown();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tickCountdown();
    });
  }

  void _tickCountdown() {
    final deadline = _deadlineAt;
    if (deadline == null) {
      return;
    }
    final remaining = deadline.difference(DateTime.now().toUtc());
    if (mounted) {
      setState(() {
        _remaining = remaining.isNegative ? Duration.zero : remaining;
      });
    }
    if (remaining <= Duration.zero && !_isExpiredHandling) {
      _handleExpiry();
    }
  }

  Future<void> _handleExpiry() async {
    _isExpiredHandling = true;
    _timer?.cancel();
    try {
      await widget.apiClient.post(
        ApiPaths.rideCancel(widget.rideId),
        body: const <String, dynamic>{},
      );
    } catch (_) {
      // Keep expiration flow moving even if cancel endpoint fails.
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection fee window expired.')),
    );
    final charter = widget.charterMode ? '1' : '0';
    context.go(
      '/rider/offers/${Uri.encodeComponent(widget.rideId)}'
      '?luggage=${widget.luggageCount}&charter=$charter',
    );
  }

  Future<void> _payConnectionFee() async {
    setState(() {
      _isPaying = true;
      _errorMessage = null;
    });
    try {
      await widget.apiClient.post(
        ApiPaths.ridePaywallPay(widget.rideId),
        body: const <String, dynamic>{},
      );
    } catch (error) {
      if (error is! ApiException || error.statusCode != 404) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = formatApiError(error);
          _isPaying = false;
        });
        return;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isPaying = false;
    });
    final charter = widget.charterMode ? '1' : '0';
    context.push(
      '/rider/seats/${Uri.encodeComponent(widget.rideId)}'
      '?offerPrice=${widget.offerPriceMinor}'
      '&charter=$charter'
      '&luggage=${widget.luggageCount}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final countdown = _formatDuration(_remaining);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Connection Fee Paywall',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          SelectableText('ride_id: ${widget.rideId}'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _PaywallRow(
                    label: 'connection_fee_minor',
                    value: _connectionFeeMinor.toString(),
                  ),
                  _PaywallRow(label: 'countdown', value: countdown),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('paywall_continue_button'),
            onPressed: (_isLoading || _isPaying || _remaining == Duration.zero)
                ? null
                : _payConnectionFee,
            child: _isPaying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: _isLoading ? null : _openPaywall,
            child: const Text('Refresh Paywall'),
          ),
          if (_isLoading) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _PaywallRow extends StatelessWidget {
  const _PaywallRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(width: 150, child: Text(label)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

Map<String, dynamic> _mockPaywallResponse(String rideId) {
  final existing = MockBackendStore.paywallByRideId[rideId];
  if (existing != null) {
    return existing;
  }
  final mocked = <String, dynamic>{
    'connection_fee_minor': 1500,
    'deadline_at': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String(),
  };
  MockBackendStore.paywallByRideId[rideId] = mocked;
  return mocked;
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
