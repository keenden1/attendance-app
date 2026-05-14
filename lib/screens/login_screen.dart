import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';
import 'biometric_raw_screen.dart';
import 'settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  
  // Hidden Admin Access
  int _adminTapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final savedId = await SupabaseService.getSavedUserSession();
    if (savedId != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => BiometricRawScreen(biometricId: savedId),
        ),
      );
    }
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final supabaseService = await SupabaseService.build();

        if (supabaseService == null) {
          throw Exception('Supabase is not configured. Please go to settings.');
        }

        final enrollee = await supabaseService.authenticate(
          _nameController.text.trim(),
          _passwordController.text.trim(),
        );

        setState(() => _isLoading = false);

        if (enrollee != null) {
          if (mounted) {
            final biometricId = enrollee['user_id']?.toString();
            if (biometricId != null && _rememberMe) {
              await SupabaseService.saveUserSession(biometricId);
            }
            
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => BiometricRawScreen(biometricId: biometricId),
                ),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid Name or ID'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _navigateToSettings() async {
    final TextEditingController passwordController = TextEditingController();
    final bool? authorized = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Access'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Enter Admin Password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (passwordController.text == 'P@ssw0rd') {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect Password'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (authorized == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SettingsScreen()),
      );
    }
  }

  void _showShareQr() async {
    // Show a small loading indicator while we check for the latest links
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      String? apkLink = prefs.getString(kApkDownloadLinkKey);
      String? webLink = prefs.getString(kWebAppLinkKey);

      // Try to fetch the latest links from Supabase if local is empty
      final service = await SupabaseService.build();
      if (service != null) {
        final config = await service.getConfig();
        
        final cloudApkLink = config?['apk_download_link']?.toString();
        if (cloudApkLink != null && cloudApkLink.isNotEmpty) {
          apkLink = cloudApkLink;
          await prefs.setString(kApkDownloadLinkKey, cloudApkLink);
        }

        final cloudWebLink = config?['web_app_link']?.toString();
        if (cloudWebLink != null && cloudWebLink.isNotEmpty) {
          webLink = cloudWebLink;
          await prefs.setString(kWebAppLinkKey, cloudWebLink);
        }
      }

      final finalApkLink = (apkLink ?? kDefaultApkLink).trim();
      final finalWebLink = (webLink ?? kDefaultWebLink).trim();

      if (!mounted) return;
      Navigator.pop(context); // Remove loading indicator

      if (finalApkLink.isEmpty && finalWebLink.isEmpty) {
        _showNoLinkDialog();
        return;
      }

      _showQrDialog(finalApkLink, finalWebLink);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorDialog('Failed to fetch sharing links: $e');
    }
  }

  void _showNoLinkDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Links Not Configured'),
        content: const Text(
          'Neither the APK nor the Web link has been set yet.\n\nPlease log in as Admin and set the links in Server Settings.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  void _showQrDialog(String apkLink, String webLink) {
    showDialog(
      context: context,
      builder: (context) {
        String currentTab = 'mobile'; // 'mobile' or 'web'
        
        return StatefulBuilder(
          builder: (context, setState) {
            final activeLink = currentTab == 'mobile' ? apkLink : webLink;
            final isApk = currentTab == 'mobile';

            return AlertDialog(
              title: const Text('Share App', textAlign: TextAlign.center),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Platform Selector
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'mobile',
                          label: Text('Mobile (APK)'),
                          icon: Icon(Icons.android_rounded, size: 18),
                        ),
                        ButtonSegment(
                          value: 'web',
                          label: Text('Web Version'),
                          icon: Icon(Icons.language_rounded, size: 18),
                        ),
                      ],
                      selected: {currentTab},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          currentTab = newSelection.first;
                        });
                      },
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    const Text('Scan this QR code or use the links below:',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 24),
                    
                    // 1. QR Code Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: QrImageView(
                        data: activeLink,
                        version: QrVersions.auto,
                        size: 160.0,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1A237E)),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // 2. Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: activeLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${isApk ? 'APK' : 'Web'} link copied to clipboard!'), 
                                  duration: const Duration(seconds: 2)
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copy'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(activeLink);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: Icon(isApk ? Icons.download_rounded : Icons.open_in_new_rounded, size: 18),
                            label: Text(isApk ? 'Download' : 'Open Web'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      activeLink,
                      style: const TextStyle(fontSize: 10, color: Colors.blue),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: const Icon(Icons.qr_code_2_rounded, color: Colors.grey),
            onPressed: _showShareQr,
            tooltip: 'Share App',
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Modern Logo Indicator (Secret Admin Access: 10 Taps)
                GestureDetector(
                  onTap: () {
                    final now = DateTime.now();
                    // Reset if more than 2 seconds between taps
                    if (_lastTapTime != null && now.difference(_lastTapTime!).inSeconds > 2) {
                      _adminTapCount = 0;
                    }
                    _lastTapTime = now;
                    _adminTapCount++;
                    
                    if (_adminTapCount >= 10) {
                      _adminTapCount = 0; // reset
                      _navigateToSettings();
                    }
                  },
                  child: Hero(
                    tag: 'app_logo',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(20),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/login_icon.png',
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'BW Attendance Checker',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to manage your attendance',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 40),
                
                // Login Card
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    elevation: 4,
                    shadowColor: Colors.black.withAlpha(15),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Welcome Back',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 32),
                            
                            // Name Field
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Employee Name',
                                hintText: 'Enter your name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            
                            // Password Field (ID)
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Employee ID',
                                hintText: 'Enter your employee ID',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword 
                                      ? Icons.visibility_off_outlined 
                                      : Icons.visibility_outlined
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your ID';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Remember Me Toggle
                            Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('Remember Me', style: TextStyle(fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            
                            // Login Button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              child: _isLoading 
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Login'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
