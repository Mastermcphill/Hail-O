import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/storage/token_storage.dart';

const String kRouteChainsLocalStorageKey = 'driver_route_chains_local';

class RouteChainScreen extends StatefulWidget {
  const RouteChainScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  @override
  State<RouteChainScreen> createState() => _RouteChainScreenState();
}

class _RouteChainScreenState extends State<RouteChainScreen> {
  final List<TextEditingController> _nodeControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  final TextEditingController _vehicleClassController = TextEditingController(
    text: 'sedan',
  );
  final TextEditingController _capacityController = TextEditingController(
    text: '4',
  );
  bool _isSaving = false;

  @override
  void dispose() {
    for (final controller in _nodeControllers) {
      controller.dispose();
    }
    _vehicleClassController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _addStop() {
    setState(() {
      _nodeControllers.add(TextEditingController());
    });
  }

  void _removeStop(int index) {
    if (_nodeControllers.length <= 2) {
      return;
    }
    setState(() {
      final controller = _nodeControllers.removeAt(index);
      controller.dispose();
    });
  }

  Future<void> _saveRouteChain() async {
    FocusScope.of(context).unfocus();
    final nodes = _nodeControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => <String, dynamic>{'name': value})
        .toList(growable: false);

    if (nodes.length < 2) {
      _showSnackBar('Add at least two stops.');
      return;
    }

    final payload = <String, dynamic>{
      'nodes': nodes,
      'vehicle_class': _vehicleClassController.text.trim().isEmpty
          ? 'sedan'
          : _vehicleClassController.text.trim(),
      'capacity': int.tryParse(_capacityController.text.trim()) ?? 4,
    };

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.apiClient.post(ApiPaths.routes, body: payload);
      if (!mounted) {
        return;
      }
      _showSnackBar('Route chain saved.');
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        await _saveLocalRouteChain(payload);
        if (!mounted) {
          return;
        }
        _showSnackBar('Endpoint unavailable. Saved locally (mock mode).');
      } else {
        if (!mounted) {
          return;
        }
        _showSnackBar(formatApiError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _saveLocalRouteChain(Map<String, dynamic> payload) async {
    final encoded = await widget.tokenStorage.readValue(
      kRouteChainsLocalStorageKey,
    );
    final existing = _asList(encoded);
    existing.add(<String, dynamic>{
      ...payload,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
    });
    await widget.tokenStorage.writeValue(
      kRouteChainsLocalStorageKey,
      jsonEncode(existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Create Route Chain',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _nodeControllers.length; i++) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _nodeControllers[i],
                        decoration: InputDecoration(
                          labelText: 'Stop ${i + 1}',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove stop',
                      onPressed: _isSaving || _nodeControllers.length <= 2
                          ? null
                          : () => _removeStop(i),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _addStop,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Stop'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vehicleClassController,
                decoration: const InputDecoration(
                  labelText: 'vehicle_class',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _capacityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'capacity',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSaving ? null : _saveRouteChain,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Route Chain'),
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

List<Map<String, dynamic>> _asList(String? encoded) {
  if (encoded == null || encoded.isEmpty) {
    return <Map<String, dynamic>>[];
  }
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          )
          .toList();
    }
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
  return <Map<String, dynamic>>[];
}
