import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

class RouteChainScreen extends StatefulWidget {
  const RouteChainScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<RouteChainScreen> createState() => _RouteChainScreenState();
}

class _RouteChainScreenState extends State<RouteChainScreen> {
  final _newStopController = TextEditingController();
  final _vehicleClassController = TextEditingController(text: 'sedan');
  final _capacityController = TextEditingController(text: '4');
  final List<String> _nodes = <String>[];
  bool _isOnline = true;
  bool _isSaving = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void dispose() {
    _newStopController.dispose();
    _vehicleClassController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  void _addNode() {
    final name = _newStopController.text.trim();
    if (name.isEmpty) {
      return;
    }
    setState(() {
      _nodes.add(name);
      _newStopController.clear();
    });
  }

  Future<void> _saveRouteChain() async {
    if (_nodes.length < 2) {
      _showSnackBar('Add at least 2 nodes to create a route chain.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final response = await widget.apiClient.post(
        ApiPaths.routesCreate,
        body: <String, dynamic>{
          'nodes': _nodes
              .map((node) => <String, dynamic>{'name': node})
              .toList(growable: false),
          'vehicle_class': _vehicleClassController.text.trim().isEmpty
              ? 'sedan'
              : _vehicleClassController.text.trim(),
          'capacity': int.tryParse(_capacityController.text.trim()) ?? 4,
          'is_online': _isOnline,
        },
      );
      if (!mounted) {
        return;
      }
      final savedLocally = response['mock_mode'] == true;
      setState(() {
        _statusMessage = savedLocally
            ? 'Saved locally (mock mode).'
            : 'Route chain saved.';
      });
      _showSnackBar(_statusMessage!);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = formatApiError(error);
      });
      _showSnackBar(_errorMessage!);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Create Route Chain',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _newStopController,
                      decoration: const InputDecoration(
                        labelText: 'Add stop node',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: _addNode, child: const Text('Add')),
                ],
              ),
              const SizedBox(height: 12),
              if (_nodes.isEmpty)
                const Text('No nodes added yet.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (var i = 0; i < _nodes.length; i++)
                      Chip(
                        label: Text('${i + 1}. ${_nodes[i]}'),
                        onDeleted: () {
                          setState(() {
                            _nodes.removeAt(i);
                          });
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Go online'),
                value: _isOnline,
                onChanged: (value) {
                  setState(() {
                    _isOnline = value;
                  });
                },
              ),
              const SizedBox(height: 16),
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
              if (_statusMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
