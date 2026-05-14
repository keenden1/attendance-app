import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import 'biometric_raw_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _bucketController = TextEditingController();
  final _apkLinkController = TextEditingController();
  final _webLinkController = TextEditingController();

  bool _keyVisible = false;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _bucketController.dispose();
    _apkLinkController.dispose();
    _webLinkController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString(kSupabaseUrlKey) ?? kDefaultSupabaseUrl;
      _keyController.text = prefs.getString(kSupabaseKeyKey) ?? kDefaultSupabaseKey;
      _bucketController.text = prefs.getString(kSupabaseBucketKey) ?? kDefaultSupabaseBucket;
      _apkLinkController.text = prefs.getString(kApkDownloadLinkKey) ?? kDefaultApkLink;
      _webLinkController.text = prefs.getString(kWebAppLinkKey) ?? kDefaultWebLink;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kSupabaseUrlKey, _urlController.text.trim());
    await prefs.setString(kSupabaseKeyKey, _keyController.text.trim());
    await prefs.setString(kSupabaseBucketKey, _bucketController.text.trim());
    await prefs.setString(kApkDownloadLinkKey, _apkLinkController.text.trim());
    await prefs.setString(kWebAppLinkKey, _webLinkController.text.trim());
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final service = SupabaseService(
        url: _urlController.text.trim(),
        key: _keyController.text.trim(),
        bucket: _bucketController.text.trim(),
      );
      final count = await service.testConnection();
      setState(() {
        _testSuccess = true;
        _testResult = 'Connected — $count file(s) found in bucket.';
      });
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Failed: $e';
      });
    } finally {
      setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Settings'),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(theme, 'Supabase Connection', Icons.cloud_sync_rounded),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Project URL',
                          hintText: 'https://xyz.supabase.co',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _keyController,
                        obscureText: !_keyVisible,
                        decoration: InputDecoration(
                          labelText: 'API Key (Anon)',
                          prefixIcon: const Icon(Icons.vpn_key_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_keyVisible ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _keyVisible = !_keyVisible),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _bucketController,
                        decoration: const InputDecoration(
                          labelText: 'Storage Bucket',
                          prefixIcon: Icon(Icons.folder_special_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _apkLinkController,
                        decoration: const InputDecoration(
                          labelText: 'APK Download Link',
                          hintText: 'https://...',
                          prefixIcon: Icon(Icons.install_mobile_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _webLinkController,
                        decoration: const InputDecoration(
                          labelText: 'Web App Link',
                          hintText: 'https://...',
                          prefixIcon: Icon(Icons.language_rounded),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_testResult != null) _buildTestResult(),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isTesting || _isSaving ? null : _testConnection,
                      icon: _isTesting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.bolt_rounded, size: 20),
                      label: const Text('Test Connection'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: theme.colorScheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving || _isTesting ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded, size: 20),
                      label: const Text('Save Changes'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              const Divider(),
              const SizedBox(height: 24),
              _buildHeader(theme, 'Administrative Actions', Icons.admin_panel_settings_rounded),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BiometricRawScreen(biometricId: null),
                      ),
                    );
                  },
                  icon: const Icon(Icons.dashboard_customize_rounded),
                  label: const Text('Launch Admin Dashboard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo[900],
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 24),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildTestResult() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _testSuccess ? Colors.green.withAlpha(15) : Colors.red.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _testSuccess ? Colors.green.withAlpha(50) : Colors.red.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(
            _testSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
            color: _testSuccess ? Colors.green[700] : Colors.red[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _testResult!,
              style: TextStyle(
                color: _testSuccess ? Colors.green[900] : Colors.red[900],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
