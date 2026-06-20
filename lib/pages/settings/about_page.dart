import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// About page with app info.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static final Uri _repoUri =
      Uri.parse('https://github.com/vimers/easy_contact_sync');
  static final Uri _issuesUri =
      Uri.parse('https://github.com/vimers/easy_contact_sync/issues');

  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = info.version);
  }

  Future<void> _openUrl(Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $uri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 32),

          // App icon
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.contact_page,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'EasyContactSync',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _version.isEmpty ? '' : 'v$_version',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),

          // Description
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'EasyContactSync is an open-source mobile app that synchronizes '
                      'your contacts via the CardDAV protocol (RFC 6352). It supports '
                      'background sync, field-level diff display, and user-driven '
                      'conflict resolution.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Features
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Features',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _featureItem(Icons.sync, 'CardDAV sync via standard protocol'),
                    _featureItem(Icons.security, 'Encrypted credential storage'),
                    _featureItem(Icons.compare, 'Field-level diff comparison'),
                    _featureItem(Icons.checklist, 'Batch & per-contact conflict resolution'),
                    _featureItem(Icons.schedule, 'Configurable background sync'),
                    _featureItem(Icons.language, 'Multi-language support (i18n)'),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Source code & issue reporting
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.code),
                    title: const Text('Source code'),
                    subtitle: const Text('github.com/vimers/easy_contact_sync'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(_repoUri),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Report an issue'),
                    subtitle: const Text(
                        'Found a bug or have a suggestion? Open an issue on GitHub.'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openUrl(_issuesUri),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Licenses
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Open Source Licenses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'EasyContactSync',
                    applicationVersion: _version,
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _featureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
