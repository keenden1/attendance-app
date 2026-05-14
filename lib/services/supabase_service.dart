import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/secrets.dart';

// Storage Keys
const String kSupabaseUrlKey = 'supabase_url';
const String kSupabaseKeyKey = 'supabase_key';
const String kSupabaseBucketKey = 'supabase_bucket';
const String kLoggedInUserIdKey = 'logged_in_user_id';
const String kApkDownloadLinkKey = 'apk_download_link';
const String kWebAppLinkKey = 'web_app_link';

// --- DEFAULT CREDENTIALS (FROM SECRETS) ---
const String kDefaultSupabaseUrl = 'https://mxckrnlamidqqpmdcaks.supabase.co';
const String kDefaultSupabaseKey = Secrets.supabaseKey;
const String kDefaultSupabaseBucket = 'biometrics';
const String kDefaultApkLink = 'https://mxckrnlamidqqpmdcaks.supabase.co/storage/v1/object/public/biometrics/attendance.apk';
const String kDefaultWebLink = 'https://attendance-app-omega-green.vercel.app/';


class SupabaseService {
  final String url;
  final String key;
  final String bucket;

  SupabaseService({required this.url, required this.key, required this.bucket});

  static Future<SupabaseService?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final sUrl = prefs.getString(kSupabaseUrlKey) ?? kDefaultSupabaseUrl;
    final sKey = prefs.getString(kSupabaseKeyKey) ?? kDefaultSupabaseKey;
    final sBucket = prefs.getString(kSupabaseBucketKey) ?? kDefaultSupabaseBucket;

    if (sUrl.isEmpty || sKey.isEmpty || sBucket.isEmpty || sKey == 'YOUR_SUPABASE_ANON_KEY') {
      return null;
    }

    return SupabaseService(url: sUrl, key: sKey, bucket: sBucket);
  }

  /// Lists all files in the storage bucket.
  Future<List<String>> listFiles() async {
    final requestUrl = '$url/storage/v1/object/list/$bucket';
    final response = await http.post(
      Uri.parse(requestUrl),
      headers: {
        'Authorization': 'Bearer $key',
        'apikey': key,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'prefix': '',
        'limit': 100,
        'offset': 0,
        'sortBy': {'column': 'name', 'order': 'desc'}
      }),
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data
          .where((item) => item['name'] != null && (item['name'] as String).endsWith('.json'))
          .map((item) => item['name'] as String)
          .toList();
    } else {
      throw Exception('Error ${response.statusCode}: Failed to list files. Check your API Key and Bucket permissions.');
    }
  }

  /// Downloads and parses a JSON file. Tries both authenticated and public endpoints.
  Future<Map<String, dynamic>> _downloadFile(String filename) async {
    final authUrl = '$url/storage/v1/object/authenticated/$bucket/$filename';
    var response = await http.get(
      Uri.parse(authUrl),
      headers: {'Authorization': 'Bearer $key', 'apikey': key},
    );

    if (response.statusCode != 200) {
      final publicUrl = '$url/storage/v1/object/public/$bucket/$filename';
      response = await http.get(Uri.parse(publicUrl));
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Error ${response.statusCode}: Failed to download $filename');
    }
  }

  /// Uploads a JSON object as a file to the bucket.
  Future<void> _uploadFile(String filename, Map<String, dynamic> content) async {
    final requestUrl = '$url/storage/v1/object/$bucket/$filename';
    final response = await http.post(
      Uri.parse(requestUrl),
      headers: {
        'Authorization': 'Bearer $key',
        'apikey': key,
        'Content-Type': 'application/json',
        'x-upsert': 'true',
      },
      body: jsonEncode(content),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to upload $filename: ${response.body}');
    }
  }

  /// Gets the shared configuration (e.g., which file is active).
  Future<Map<String, dynamic>?> getConfig() async {
    try {
      return await _downloadFile('app_config.json');
    } catch (_) {
      return null;
    }
  }

  /// Sets the shared configuration.
  Future<void> setConfig(Map<String, dynamic> config) async {
    await _uploadFile('app_config.json', config);
  }

  Future<Map<String, dynamic>> fetchAllData({bool forceAll = false}) async {
    final files = await listFiles();
    final List<Map<String, dynamic>> allEnrollees = [];
    final List<Map<String, dynamic>> allAttendance = [];
    final Set<String> seenEnrolleeIds = {};
    final Set<String> seenAttendanceKeys = {};
    String? latestFetchTime;

    // Check for active file in config
    String? activeFile;
    if (!forceAll) {
      final config = await getConfig();
      activeFile = config?['active_file']?.toString();
    }

    // Filter files
    final List<String> targetFiles = files.where((f) {
      if (f == 'app_config.json') return false;
      if (activeFile != null && activeFile.isNotEmpty) return f == activeFile;
      return true;
    }).toList();

    targetFiles.sort((a, b) => b.compareTo(a));

    for (final filename in targetFiles) {
      try {
        final data = await _downloadFile(filename);
        
        final currentFetchTime = data['fetch_time']?.toString();
        if (currentFetchTime != null) {
          if (latestFetchTime == null || currentFetchTime.compareTo(latestFetchTime) > 0) {
            latestFetchTime = currentFetchTime;
          }
        }

        // Process Enrollees
        final enrollees = (data['enrollees'] as List? ?? []);
        for (final item in enrollees) {
          try {
            final enrollee = Map<String, dynamic>.from(item as Map);
            final String id = (enrollee['user_id']?.toString() ?? enrollee['uid']?.toString() ?? '').trim();
            if (id.isNotEmpty && !seenEnrolleeIds.contains(id)) {
              allEnrollees.add(enrollee);
              seenEnrolleeIds.add(id);
            }
          } catch (_) {}
        }

        // Process Attendance
        final attendance = (data['attendance'] as List? ?? []);
        for (final item in attendance) {
          try {
            final record = Map<String, dynamic>.from(item as Map);
            final String id = record['id']?.toString() ?? '';
            final String ts = record['timestamp']?.toString() ?? '';
            final String uniqueKey = '$id|$ts';

            if (id.isNotEmpty && ts.isNotEmpty && !seenAttendanceKeys.contains(uniqueKey)) {
              allAttendance.add(record);
              seenAttendanceKeys.add(uniqueKey);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    return {
      'enrollees': allEnrollees, 
      'attendance': allAttendance,
      'fetch_time': latestFetchTime,
    };
  }

  Future<Map<String, dynamic>?> authenticate(String namePattern, String idPassword) async {
    final files = await listFiles();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.compareTo(a));

    String clean(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final searchTerms = namePattern.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();
    if (searchTerms.isEmpty) return null;
    final String cleanPassword = idPassword.trim();

    for (final filename in files) {
      try {
        final data = await _downloadFile(filename);
        final enrollees = (data['enrollees'] as List? ?? []);
        for (final item in enrollees) {
          final enrollee = Map<String, dynamic>.from(item as Map);
          final String normalizedDBName = clean(enrollee['name']?.toString() ?? '');
          final String userId = (enrollee['user_id']?.toString() ?? '').trim();
          final String uid = (enrollee['uid']?.toString() ?? '').trim();

          if (searchTerms.every((term) => normalizedDBName.contains(term)) && (userId == cleanPassword || uid == cleanPassword)) {
            return enrollee;
          }
        }
      } on Exception catch (e) {
        if (e.toString().contains('403') || e.toString().contains('401')) {
          rethrow;
        }
        continue;
      }
    }
    return null;
  }

  Future<int> testConnection() async {
    final files = await listFiles();
    return files.length;
  }

  static Future<void> saveUserSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLoggedInUserIdKey, userId);
  }

  static Future<String?> getSavedUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kLoggedInUserIdKey);
  }

  static Future<void> clearUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kLoggedInUserIdKey);
  }
}
