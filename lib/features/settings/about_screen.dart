import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config/api_config.dart';
import '../../core/util/ids.dart';
import '../../widgets/loading_overlay.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late Future<PackageInfo> _packageInfoFuture;
  bool _copying = false;

  static const String _release = String.fromEnvironment(
    'HAILO_RELEASE',
    defaultValue: 'local',
  );
  static const String _commitSha = String.fromEnvironment(
    'HAILO_COMMIT_SHA',
    defaultValue: 'unknown',
  );
  static const String _envFromDefine = String.fromEnvironment(
    'HAILO_ENV',
    defaultValue: '',
  );
  static const bool _useProd = bool.fromEnvironment(
    'HAILO_USE_PROD',
    defaultValue: false,
  );

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _packageInfoFuture,
      builder: (context, snapshot) {
        final packageInfo = snapshot.data;
        final version = packageInfo?.version ?? 'unknown';
        final buildNumber = packageInfo?.buildNumber ?? 'unknown';
        final appName = packageInfo?.appName ?? 'Hail-O Core';

        return LoadingOverlay(
          isLoading: _copying,
          message: 'Preparing diagnostics...',
          child: Scaffold(
            appBar: AppBar(title: const Text('About & Diagnostics')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(appName, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                _InfoTile(label: 'Version', value: version),
                _InfoTile(label: 'Build', value: buildNumber),
                _InfoTile(label: 'Environment', value: _environmentLabel()),
                _InfoTile(label: 'Base URL', value: ApiConfig.baseUrl),
                _InfoTile(label: 'Release', value: _release),
                _InfoTile(label: 'Commit', value: _commitSha),
                const SizedBox(height: 12),
                Semantics(
                  label: 'Copy diagnostics button',
                  button: true,
                  child: FilledButton.icon(
                    onPressed: _copying
                        ? null
                        : () => _copyDiagnostics(
                            version: version,
                            buildNumber: buildNumber,
                          ),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy diagnostics'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _environmentLabel() {
    if (_envFromDefine.trim().isNotEmpty) {
      return _envFromDefine.trim();
    }
    return _useProd ? 'prod' : 'dev';
  }

  Future<void> _copyDiagnostics({
    required String version,
    required String buildNumber,
  }) async {
    setState(() {
      _copying = true;
    });
    final payload = <String, String>{
      'app_version': version,
      'build': buildNumber,
      'environment': _environmentLabel(),
      'base_url': ApiConfig.baseUrl,
      'release': _release,
      'commit': _commitSha,
      'request_id': newRequestId(),
      'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
    };
    final diagnosticsText = payload.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: diagnosticsText));
    if (!mounted) {
      return;
    }
    setState(() {
      _copying = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostics copied to clipboard')),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(value),
    );
  }
}
