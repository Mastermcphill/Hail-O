import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_error.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

class DriverAutosavePanel extends StatefulWidget {
  const DriverAutosavePanel({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<DriverAutosavePanel> createState() => _DriverAutosavePanelState();
}

class _DriverAutosavePanelState extends State<DriverAutosavePanel> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _status = const <String, dynamic>{};
  List<Map<String, dynamic>> _ledger = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.apiClient.get(ApiPaths.autosaveStatus);
      final ledger = await widget.apiClient.get(ApiPaths.autosaveLedger);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = Map<String, dynamic>.from(status);
        _ledger = ((ledger['ledger'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (entry) => entry.map(
                (key, value) =>
                    MapEntry<String, dynamic>(key.toString(), value),
              ),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final envelope = ApiErrorEnvelope.fromException(error);
      setState(() {
        _loading = false;
        if (error is ApiException &&
            (error.statusCode == 410 ||
                (error.code ?? '').toUpperCase() ==
                    'WALLET_CUSTODY_DISABLED')) {
          _error = 'Payout Autosave is unavailable on this build.';
          return;
        }
        _error = envelope.friendlyMessage;
      });
    }
  }

  Future<void> _configure() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _AutosaveConfigureDialog(),
    );
    if (!mounted || payload == null) {
      return;
    }
    await _runBusyAction(() async {
      await widget.apiClient.post(ApiPaths.autosaveConfigure, body: payload);
      await _refresh();
    });
  }

  Future<void> _disable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Disable Autosave'),
          content: const Text(
            'Leaving early forfeits your bonus and may trigger an exit fee '
            'deducted from future payouts.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Disable'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    await _runBusyAction(() async {
      await widget.apiClient.post(
        ApiPaths.autosaveDisable,
        body: const <String, dynamic>{'reason': 'driver_requested'},
      );
      await _refresh();
    });
  }

  Future<void> _runBusyAction(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final envelope = ApiErrorEnvelope.fromException(error);
      setState(() {
        _error = envelope.friendlyMessage;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final configured = _status['configured'] == true;
    final totals = Map<String, dynamic>.from(
      (_status['totals'] as Map?) ?? const {},
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.savings_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Payout Autosave',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_loading || _busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Split eligible driver payouts between your main destination '
              'and your savings destination.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_loading)
              const SizedBox.shrink()
            else if (!configured)
              Text(
                'Not configured yet. Set your main and savings destinations to start splitting payouts.',
                style: theme.textTheme.bodyMedium,
              )
            else ...<Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _FactChip(
                    label: 'Status',
                    value: '${_status['status'] ?? '-'}',
                  ),
                  _FactChip(label: 'Tier', value: '${_status['tier'] ?? '-'}'),
                  _FactChip(
                    label: 'Percent',
                    value: '${_status['autosave_percent'] ?? 0}%',
                  ),
                  _FactChip(
                    label: 'Bonus',
                    value: _status['bonus_eligible'] == true
                        ? 'Eligible'
                        : 'Stopped',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Maturity: ${_status['maturity_at'] ?? 'n/a'}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Saved: ${totals['total_autosaved_minor'] ?? 0} minor',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Bonus paid: ${totals['total_bonus_minor'] ?? 0} minor',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                'Exit fees: ${totals['total_exit_fees_minor'] ?? 0} minor',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Leaving early forfeits your bonus and may trigger an exit fee deducted from future payouts.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text('Recent activity', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_ledger.isEmpty)
                Text(
                  'No autosave activity yet.',
                  style: theme.textTheme.bodySmall,
                )
              else
                ..._ledger
                    .take(5)
                    .map(
                      (entry) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${entry['id'] ?? '-'}'),
                        ),
                        title: Text('${entry['entry_type'] ?? '-'}'),
                        subtitle: Text('${entry['created_at'] ?? ''}'),
                        trailing: Text('${entry['amount_minor'] ?? 0}'),
                      ),
                    ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: _busy ? null : _configure,
                  child: Text(configured ? 'Update Plan' : 'Set Up Autosave'),
                ),
                if (configured)
                  OutlinedButton(
                    onPressed: _busy ? null : _disable,
                    child: const Text('Disable Plan'),
                  ),
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text('$label: $value'),
      ),
    );
  }
}

class _AutosaveConfigureDialog extends StatefulWidget {
  const _AutosaveConfigureDialog();

  @override
  State<_AutosaveConfigureDialog> createState() =>
      _AutosaveConfigureDialogState();
}

class _AutosaveConfigureDialogState extends State<_AutosaveConfigureDialog> {
  final _mainAccount = TextEditingController(text: '0001112223');
  final _mainBankCode = TextEditingController(text: '058');
  final _mainName = TextEditingController(text: 'Main Destination');
  final _saveAccount = TextEditingController(text: '4445556667');
  final _saveBankCode = TextEditingController(text: '033');
  final _saveName = TextEditingController(text: 'Savings Destination');
  int _tier = 1;
  int _percent = 5;

  @override
  void dispose() {
    _mainAccount.dispose();
    _mainBankCode.dispose();
    _mainName.dispose();
    _saveAccount.dispose();
    _saveBankCode.dispose();
    _saveName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Autosave'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<int>(
              initialValue: _tier,
              decoration: const InputDecoration(labelText: 'Tier'),
              items: const <DropdownMenuItem<int>>[
                DropdownMenuItem(value: 1, child: Text('Tier 1 (30 days)')),
                DropdownMenuItem(value: 2, child: Text('Tier 2 (120 days)')),
                DropdownMenuItem(value: 3, child: Text('Tier 3 (210 days)')),
                DropdownMenuItem(value: 4, child: Text('Tier 4 (330 days)')),
              ],
              onChanged: (value) => setState(() => _tier = value ?? 1),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _percent,
              decoration: const InputDecoration(labelText: 'Autosave percent'),
              items: List<DropdownMenuItem<int>>.generate(10, (index) {
                final value = (index + 1) * 5;
                return DropdownMenuItem(value: value, child: Text('$value%'));
              }),
              onChanged: (value) => setState(() => _percent = value ?? 5),
            ),
            const SizedBox(height: 12),
            _field(_mainAccount, 'Main account number'),
            const SizedBox(height: 8),
            _field(_mainBankCode, 'Main bank code'),
            const SizedBox(height: 8),
            _field(_mainName, 'Main account name'),
            const SizedBox(height: 12),
            _field(_saveAccount, 'Savings account number'),
            const SizedBox(height: 8),
            _field(_saveBankCode, 'Savings bank code'),
            const SizedBox(height: 8),
            _field(_saveName, 'Savings account name'),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(<String, dynamic>{
              'autosave_enabled': true,
              'tier': _tier,
              'autosave_percent': _percent,
              'main_bank': <String, dynamic>{
                'account_number': _mainAccount.text.trim(),
                'bank_code': _mainBankCode.text.trim(),
                'name': _mainName.text.trim(),
              },
              'savings_bank': <String, dynamic>{
                'account_number': _saveAccount.text.trim(),
                'bank_code': _saveBankCode.text.trim(),
                'name': _saveName.text.trim(),
              },
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
