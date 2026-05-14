import 'attendance.dart';

class User {
  final String id;
  final String? biometricId;
  final String name;
  final String email;
  final String password;
  final String role;
  final List<Attendance> attendanceRecords;

  User({
    required this.id,
    this.biometricId,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.attendanceRecords,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'biometricId': biometricId,
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      'attendanceRecords': attendanceRecords.map((e) => e.toJson()).toList(),
    };
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      biometricId: json['biometricId'],
      name: json['name'],
      email: json['email'],
      password: json['password'],
      role: json['role'],
      attendanceRecords: (json['attendanceRecords'] as List)
          .map((e) => Attendance.fromJson(e))
          .toList(),
    );
  }
}
