import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/error_log_provider.dart';
import '../../providers/settings_provider.dart';
import 'account_edit_page.dart';
import 'about_page.dart';
import 'error_log_page.dart';

/// Main settings page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Accounts section
          const _SectionHeader(title: 'CardDAV Accounts'),
          accountsAsync.when(
            data: (accounts) {
              return Column(
                children: [
                  ...accounts.map((account) => ListTile(
                        leading: const Icon(Icons.cloud),
                        title: Text(account.username),
                        subtitle: Text(account.serverUrl),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _confirmDelete(context, ref, account.id!),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AccountEditPage(account: account),
                            ),
                          );
                        },
                      )),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Add Account'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AccountEditPage()),
                      );
                    },
                  ),
                ],
              );
            },
            loading: () => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Add Account'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountEditPage()),
                    );
                  },
                ),
              ],
            ),
            error: (e, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $e'),
                ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Add Account'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountEditPage()),
                    );
                  },
                ),
              ],
            ),
          ),

          const Divider(),

          // Sync frequency
          const _SectionHeader(title: 'Sync Settings'),
          _SyncFrequencyTile(),

          const Divider(),

          // Diagnostics
          const _SectionHeader(title: 'Diagnostics'),
          const _ErrorLogTile(),

          const Divider(),

          // About
          const _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About EasyContactSync'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, int accountId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure you want to delete this account? All sync data will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(accountNotifierProvider.notifier).deleteAccount(accountId);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _SyncFrequencyTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intervalAsync = ref.watch(syncIntervalProvider);

    return ListTile(
      leading: const Icon(Icons.schedule),
      title: const Text('Sync Frequency'),
      subtitle: intervalAsync.when(
        data: (minutes) => Text(_labelForInterval(minutes)),
        loading: () => const Text('Loading...'),
        error: (_, __) => const Text('Error'),
      ),
      onTap: () => _showIntervalPicker(context, ref),
    );
  }

  void _showIntervalPicker(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Sync Frequency'),
        children: [
          _intervalOption(ctx, ref, 15, 'Every 15 minutes'),
          _intervalOption(ctx, ref, 30, 'Every 30 minutes'),
          _intervalOption(ctx, ref, 60, 'Every hour'),
          _intervalOption(ctx, ref, 360, 'Every 6 hours'),
          _intervalOption(ctx, ref, 0, 'Manual only'),
        ],
      ),
    );
  }

  SimpleDialogOption _intervalOption(BuildContext ctx, WidgetRef ref, int minutes, String label) {
    return SimpleDialogOption(
      onPressed: () {
        ref.read(settingsNotifierProvider.notifier).updateSyncInterval(minutes);
        Navigator.pop(ctx);
      },
      child: Text(label),
    );
  }

  String _labelForInterval(int minutes) {
    return switch (minutes) {
      15 => 'Every 15 minutes',
      30 => 'Every 30 minutes',
      60 => 'Every hour',
      360 => 'Every 6 hours',
      0 => 'Manual only',
      _ => 'Every $minutes minutes',
    };
  }
}

/// Settings entry for the persisted error log, with a red badge when there are
/// unread entries.
class _ErrorLogTile extends ConsumerWidget {
  const _ErrorLogTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      errorLogProvider.select((errors) =>
          errors.where((e) => !e.isRead).length),
    );

    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text('Error Log'),
      subtitle: Text(unread > 0 ? '$unread unread error(s)' : 'No new errors'),
      trailing: unread > 0
          ? Badge(
              backgroundColor: Colors.red,
              label: Text('$unread'),
            )
          : const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ErrorLogPage()),
        );
      },
    );
  }
}
