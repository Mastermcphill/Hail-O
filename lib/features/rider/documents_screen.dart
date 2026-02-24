import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

class RiderDocumentsScreen extends StatefulWidget {
  const RiderDocumentsScreen({
    super.key,
    required this.apiClient,
    this.returnTo,
  });

  final ApiClient apiClient;
  final String? returnTo;

  @override
  State<RiderDocumentsScreen> createState() => _RiderDocumentsScreenState();
}

class _RiderDocumentsScreenState extends State<RiderDocumentsScreen> {
  final TextEditingController _fileRefController = TextEditingController();
  final TextEditingController _countryController = TextEditingController(
    text: 'NG',
  );
  final TextEditingController _expiresAtController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String _docType = 'passport';
  List<Map<String, dynamic>> _documents = <Map<String, dynamic>>[];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fileRefController.dispose();
    _countryController.dispose();
    _expiresAtController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.apiClient.get(ApiPaths.meDocuments);
      final rows =
          (response['documents'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (row) => row.map(
                  (key, value) =>
                      MapEntry<String, dynamic>(key.toString(), value),
                ),
              )
              .toList(growable: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _documents = rows;
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

  Future<void> _saveDocument() async {
    final fileRef = _fileRefController.text.trim();
    if (fileRef.isEmpty) {
      _showSnackBar('Document reference is required.');
      return;
    }

    final expiresAt = _expiresAtController.text.trim();
    if (expiresAt.isNotEmpty && DateTime.tryParse(expiresAt) == null) {
      _showSnackBar('expires_at must be a valid ISO date/time.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await widget.apiClient.post(
        ApiPaths.meDocuments,
        body: <String, dynamic>{
          'doc_type': _docType,
          'file_ref': fileRef,
          'country': _countryController.text.trim().toUpperCase(),
          if (expiresAt.isNotEmpty)
            'expires_at': DateTime.parse(expiresAt).toUtc().toIso8601String(),
          'verified': true,
        },
      );

      if (!mounted) {
        return;
      }
      _fileRefController.clear();
      _expiresAtController.clear();
      await _load();
      if (!mounted) {
        return;
      }
      _showSnackBar('Document saved.');
      if (widget.returnTo != null && widget.returnTo!.trim().isNotEmpty) {
        context.go(widget.returnTo!);
      }
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
          _isSubmitting = false;
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
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Cross-Border Documents',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Upload Passport or ECOWAS ID to unlock international rides.',
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _docType,
                decoration: const InputDecoration(
                  labelText: 'doc_type',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'passport', child: Text('passport')),
                  DropdownMenuItem(
                    value: 'ecowas_id',
                    child: Text('ecowas_id'),
                  ),
                ],
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _docType = value;
                        });
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fileRefController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'file_ref',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. local_upload://passport_front.png',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _countryController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'country (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _expiresAtController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: 'expires_at (ISO, optional)',
                  border: OutlineInputBorder(),
                  hintText: '2028-12-31T00:00:00Z',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSubmitting ? null : _saveDocument,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Document'),
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  Text(
                    'Uploaded Documents',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isLoading ? null : _load,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                )
              else if (_documents.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('No documents saved yet.'),
                )
              else
                Column(
                  children: _documents
                      .map((doc) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              '${doc['doc_type'] ?? '-'} - ${doc['status'] ?? '-'}',
                            ),
                            subtitle: Text(
                              'file_ref: ${doc['file_ref'] ?? '-'}\n'
                              'expires_at: ${doc['expires_at'] ?? '-'}',
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
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
