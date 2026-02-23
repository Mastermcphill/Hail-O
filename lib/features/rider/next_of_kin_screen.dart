import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/storage/token_storage.dart';

const String kNextOfKinLocalStorageKey = 'rider_next_of_kin_local';

class NextOfKinScreen extends StatefulWidget {
  const NextOfKinScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
    this.returnTo = '/rider/request',
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final String returnTo;

  @override
  State<NextOfKinScreen> createState() => _NextOfKinScreenState();
}

class _NextOfKinScreenState extends State<NextOfKinScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _prefillFromLocal();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  Future<void> _prefillFromLocal() async {
    final encoded = await widget.tokenStorage.readValue(
      kNextOfKinLocalStorageKey,
    );
    if (!mounted || encoded == null || encoded.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(encoded);
      final map = _asMap(decoded);
      _fullNameController.text = _asString(map['full_name']);
      _phoneController.text = _asString(map['phone']);
      _relationshipController.text = _asString(map['relationship']);
      setState(() {});
    } catch (_) {
      // Keep empty defaults when local cache is malformed.
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final payload = <String, dynamic>{
      'full_name': _fullNameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'relationship': _relationshipController.text.trim(),
    };

    if (_asString(payload['full_name']).isEmpty ||
        _asString(payload['phone']).isEmpty ||
        _asString(payload['relationship']).isEmpty) {
      _showSnackBar('All fields are required.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.apiClient.post(ApiPaths.nextOfKin, body: payload);
      await widget.tokenStorage.writeValue(
        kNextOfKinLocalStorageKey,
        jsonEncode(payload),
      );
      if (!mounted) {
        return;
      }
      context.go(widget.returnTo);
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        await widget.tokenStorage.writeValue(
          kNextOfKinLocalStorageKey,
          jsonEncode(payload),
        );
        if (!mounted) {
          return;
        }
        _showSnackBar('Endpoint unavailable. Saved locally.');
        context.go(widget.returnTo);
        return;
      }
      if (!mounted) {
        return;
      }
      _showSnackBar(formatApiError(error));
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Next of Kin',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'This is required before requesting a ride.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _fullNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'full_name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _relationshipController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _isSaving ? null : _save(),
                decoration: const InputDecoration(
                  labelText: 'relationship',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Next of Kin'),
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

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry<String, dynamic>(key.toString(), mapValue),
    );
  }
  return <String, dynamic>{};
}

String _asString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}
