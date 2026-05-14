import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import 'biometric_data_service.dart';

class JsonStorageService {
  static const String _storageKey = 'employee_data_json';

  Future<List<User>> getUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? contents = prefs.getString(_storageKey);
      
      if (contents == null) {
        return await _seedInitialData();
      }
      
      final List<dynamic> jsonList = json.decode(contents);
      return jsonList.map((e) => User.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveUsers(List<User> users) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = json.encode(users.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonString);
  }

  Future<User?> authenticate(String loginId, String password) async {
    final users = await getUsers();
    try {
      return users.firstWhere(
        (u) => (u.email == loginId || u.id == loginId) && u.password == password,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> importBiometricData(String rawJson) async {
    final users = await getUsers();
    final updatedUsers = BiometricDataService.importLogs(rawJson, users);
    await saveUsers(updatedUsers);
  }

  Future<void> importEnrolleesData(String rawJson) async {
    final users = await getUsers();
    final updatedUsers = BiometricDataService.importEnrollees(rawJson, users);
    await saveUsers(updatedUsers);
  }

  Future<List<User>> _seedInitialData() async {
    final initialUsers = [
      User(
        id: 'EMP001',
        biometricId: '7909',
        name: 'Admin User',
        email: 'admin@company.com',
        password: 'password123',
        role: 'Admin',
        attendanceRecords: [],
      ),
      User(
        id: 'EMP002',
        biometricId: '7682',
        name: 'John Doe',
        email: 'john@company.com',
        password: 'password123',
        role: 'Employee',
        attendanceRecords: [],
      ),
    ];
    await saveUsers(initialUsers);
    return initialUsers;
  }
}
