import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../models/account.dart';
import '../../providers/accounts_provider.dart';
import '../../services/database_service.dart';
import '../qr_scan_page.dart';

/// Page for adding or editing a CardDAV account.
class AccountEditPage extends ConsumerStatefulWidget {
  final Account? account;

  const AccountEditPage({super.key, this.account});

  @override
  ConsumerState<AccountEditPage> createState() => _AccountEditPageState();
}

class _AccountEditPageState extends ConsumerState<AccountEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult; // null = not tested, success message, or error message
  bool _testSuccess = false;

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _serverUrlController.text = widget.account!.serverUrl;
      _usernameController.text = widget.account!.username;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Account' : 'Add Account'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Server URL
            TextFormField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://carddav.example.com',
                prefixIcon: const Icon(Icons.cloud_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan QR code',
                  onPressed: _isSaving ? null : _scanQr,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a server URL';
                }
                if (!value.startsWith('http')) {
                  return 'URL must start with http:// or https://';
                }
                return null;
              },
              keyboardType: TextInputType.url,
              enabled: !_isSaving,
              onChanged: (_) => _clearTestResult(),
            ),
            const SizedBox(height: 16),

            // Username
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'user@example.com',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a username';
                }
                return null;
              },
              keyboardType: TextInputType.emailAddress,
              enabled: !_isSaving,
              onChanged: (_) => _clearTestResult(),
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: _isEditing ? 'Leave blank to keep current' : 'Enter password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              obscureText: _obscurePassword,
              validator: (value) {
                if (!_isEditing && (value == null || value.isEmpty)) {
                  return 'Please enter a password';
                }
                return null;
              },
              enabled: !_isSaving,
              onChanged: (_) => _clearTestResult(),
            ),
            const SizedBox(height: 24),

            // Test Connection button
            OutlinedButton.icon(
              onPressed: _isTesting || _isSaving ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
            ),

            // Test result
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testSuccess
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess ? Icons.check_circle : Icons.error,
                      color: _testSuccess ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          color: _testSuccess ? Colors.green[800] : Colors.red[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Save button
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save'),
            ),

            // Info card
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your password will be encrypted and stored securely on this device using platform-native encryption (Android Keystore / iOS Keychain).',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearTestResult() {
    if (_testResult != null) {
      setState(() {
        _testResult = null;
        _testSuccess = false;
      });
    }
  }

  /// Open the QR scanner and fill the Server URL field with the result.
  Future<void> _scanQr() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (url == null) return;
    setState(() {
      _serverUrlController.text = url;
    });
    _clearTestResult();
  }

  /// Test CardDAV connection by sending a PROPFIND to the server.
  Future<void> _testConnection() async {
    if (_serverUrlController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() {
        _testResult = 'Please fill in all fields first';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final serverUrl = _serverUrlController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      // Try PROPFIND on .well-known/carddav first, then server root
      final urls = [
        '$serverUrl/.well-known/carddav',
        serverUrl,
      ];

      http.Response? response;
      for (final url in urls) {
        try {
          final request = http.Request('PROPFIND', Uri.parse(url));
          request.headers['Authorization'] =
              'Basic ${base64Encode(utf8.encode('$username:$password'))}';
          request.headers['Content-Type'] = 'application/xml; charset=utf-8';
          request.headers['Depth'] = '0';
          request.body = '''<?xml version="1.0" encoding="utf-8"?>
<propfind xmlns="DAV:">
  <prop>
    <current-user-principal/>
  </prop>
</propfind>''';

          final streamed = await request.send().timeout(const Duration(seconds: 10));
          response = await http.Response.fromStream(streamed);

          if (response.statusCode == 207 || response.statusCode == 200) {
            break;
          }
        } catch (_) {
          continue;
        }
      }

      if (response != null && (response.statusCode == 207 || response.statusCode == 200)) {
        setState(() {
          _testResult = 'Connection successful! Server is reachable.';
          _testSuccess = true;
        });
      } else if (response != null && (response.statusCode == 401 || response.statusCode == 403)) {
        setState(() {
          _testResult = 'Server reachable but authentication failed. Check username/password.';
          _testSuccess = false;
        });
      } else {
        final code = response?.statusCode ?? 'N/A';
        setState(() {
          _testResult = 'Server returned status $code. Check the server URL.';
          _testSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Connection failed: ${e.toString().replaceAll('Exception: ', '')}';
        _testSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (_isEditing) {
        final secureStorage = ref.read(secureStorageProvider);
        if (_passwordController.text.isNotEmpty) {
          await secureStorage.savePassword(widget.account!.id!, _passwordController.text);
        }
      } else {
        print('DEBUG: Adding account...');
        await ref.read(accountNotifierProvider.notifier).addAccount(
              serverUrl: _serverUrlController.text.trim(),
              username: _usernameController.text.trim(),
              password: _passwordController.text,
            );
        print('DEBUG: Account added successfully');
      }

      if (mounted) Navigator.pop(context);
    } catch (e, stackTrace) {
      print('DEBUG: Save error: $e');
      print('DEBUG: StackTrace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
