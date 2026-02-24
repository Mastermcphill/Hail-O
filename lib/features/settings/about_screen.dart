import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../config/api_config.dart';
import '../../core/observability/app_observability.dart';
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
  bool _sendingSentrySmoke = false;

  static const String _release = String.fromEnvironment(
    'HAILO_RELEASE',
    defaultValue: 'local',
  );
  static const String _commitSha = String.fromEnvironment(
    'HAILO_COMMIT_SHA',
    defaultValue: 'unknown',
  );
  static const bool _enableSentrySmokeControls = bool.fromEnvironment(
    'HAILO_ENABLE_SENTRY_SMOKE',
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
                _InfoTile(
                  label: 'Environment',
                  value: ApiConfig.environmentName,
                ),
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
                if (_showSentrySmokeControls) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    'Observability smoke (non-production)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _sendingSentrySmoke
                        ? null
                        : _sendSentryTestEvent,
                    icon: const Icon(Icons.radar),
                    label: const Text('Send Sentry test event'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _sendingSentrySmoke ? null : _confirmCrashDrill,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Trigger crash drill'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _showSentrySmokeControls {
    return _enableSentrySmokeControls &&
        ApiConfig.environment != HailoEnvironment.prod;
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
      'environment': ApiConfig.environmentName,
      'base_url': ApiConfig.baseUrl,
      'release': _release,
      'commit': _commitSha,
      'request_id': AppObservability.lastRequestId ?? newRequestId(),
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

  Future<void> _sendSentryTestEvent() async {
    setState(() {
      _sendingSentrySmoke = true;
    });
    try {
      final requestId = AppObservability.lastRequestId ?? newRequestId();
      await Sentry.configureScope((scope) {
        scope.setTag('sentry_smoke', 'true');
        scope.setTag('request_id', requestId);
      });
      await Sentry.captureMessage(
        'hailo_mobile_sentry_smoke',
        level: SentryLevel.warning,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sentry test event sent')));
    } finally {
      if (mounted) {
        setState(() {
          _sendingSentrySmoke = false;
        });
      }
    }
  }

  Future<void> _confirmCrashDrill() async {
    final shouldCrash = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Run Crash Drill'),
          content: const Text(
            'This will crash the app intentionally to verify crash reporting.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Crash now'),
            ),
          ],
        );
      },
    );
    if (shouldCrash != true) {
      return;
    }
    await Sentry.addBreadcrumb(
      Breadcrumb(
        category: 'smoke',
        message: 'manual_crash_drill_triggered',
        level: SentryLevel.warning,
      ),
    );
    Future<void>.microtask(() {
      throw StateError('hailo_manual_sentry_crash_drill');
    });
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
