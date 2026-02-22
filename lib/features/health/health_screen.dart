import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({
    super.key,
    required this.apiClient,
  });

  final ApiClient apiClient;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  bool _isOk = false;
  String _gitSha = '-';
  String _alembicHead = '-';

  @override
  void initState() {
    super.initState();
    _loadHealth();
  }

  Future<void> _loadHealth() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.get(ApiPaths.health);
      final build = _asMap(response['build']);

      final gitSha = _pickFirstString(<dynamic>[
        response['git_sha'],
        build['git_sha'],
        build['commit_sha'],
        build['commit'],
      ]);

      final alembicHead = _pickFirstString(<dynamic>[
        response['alembic_head'],
        build['alembic_head'],
        response['migration_head'],
        build['migration_head'],
      ]);

      if (!mounted) {
        return;
      }
      setState(() {
        _isOk = response['ok'] == true;
        _gitSha = gitSha ?? '-';
        _alembicHead = alembicHead ?? '-';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = formatApiError(error);
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Backend /health',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _isLoading ? null : _loadHealth,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Expanded(
              child: Center(
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            )
          else
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _HealthRow(
                            label: 'ok status',
                            value: _isOk ? 'true' : 'false',
                          ),
                          const Divider(),
                          _HealthRow(label: 'git_sha', value: _gitSha),
                          const Divider(),
                          _HealthRow(
                            label: 'alembic_head',
                            value: _alembicHead,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 12),
        SelectableText(value),
      ],
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}

String? _pickFirstString(List<dynamic> values) {
  for (final value in values) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}
