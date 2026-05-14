import 'dart:convert';
import '../models/user.dart';
import '../models/attendance.dart';

class BiometricDataService {
  /// Parses the raw biometric JSON and maps it to user attendance records.
  /// This logic groups logs by ID and Date, taking the min timestamp as In
  /// and the max timestamp as Out.
  static List<User> importLogs(String rawJson, List<User> currentUsers) {
    try {
      final Map<String, dynamic> data = json.decode(rawJson);
      final List<dynamic> logs = data['logs'];
      
      // Grouping: { biometricId: { date: [timestamps] } }
      Map<String, Map<String, List<DateTime>>> groupedLogs = {};
      
      for (var log in logs) {
        String id = log['id'].toString();
        String timestampStr = log['timestamp'];
        DateTime timestamp = DateTime.parse(timestampStr);
        String date = timestampStr.split(' ')[0]; // yyyy-MM-dd
        
        groupedLogs.putIfAbsent(id, () => {});
        groupedLogs[id]!.putIfAbsent(date, () => []);
        groupedLogs[id]![date]!.add(timestamp);
      }
      
      // Update existing users
      List<User> updatedUsers = currentUsers.map((user) {
        if (user.biometricId == null || !groupedLogs.containsKey(user.biometricId)) {
          return user;
        }
        
        Map<String, List<DateTime>> userLogs = groupedLogs[user.biometricId]!;
        List<Attendance> newRecords = List.from(user.attendanceRecords);
        
        userLogs.forEach((date, times) {
          times.sort();
          DateTime minTime = times.first;
          DateTime maxTime = times.last;
          
          String checkIn = _formatTime(minTime);
          String? checkOut = times.length > 1 ? _formatTime(maxTime) : null;
          
          // Check if record already exists for this date
          int existingIndex = newRecords.indexWhere((r) => r.date == date);
          
          Attendance record = Attendance(
            date: date,
            status: minTime.hour >= 9 && minTime.minute > 0 ? 'late' : 'present',
            checkInTime: checkIn,
            checkOutTime: checkOut,
          );
          
          if (existingIndex != -1) {
            newRecords[existingIndex] = record;
          } else {
            newRecords.add(record);
          }
        });
        
        return User(
          id: user.id,
          biometricId: user.biometricId,
          name: user.name,
          email: user.email,
          password: user.password,
          role: user.role,
          attendanceRecords: newRecords,
        );
      }).toList();
      
      return updatedUsers;
    } catch (e) {
      return currentUsers;
    }
  }

  static String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Parses the raw enrollee JSON and creates/updates users.
  /// name -> username (email/login id)
  /// user_id -> password and biometricId
  static List<User> importEnrollees(String rawJson, List<User> currentUsers) {
    try {
      final Map<String, dynamic> data = json.decode(rawJson);
      final List<dynamic> enrollees = data['enrollees'];
      
      List<User> updatedUsers = List.from(currentUsers);
      
      for (var enrollee in enrollees) {
        String userId = enrollee['user_id'].toString();
        String name = enrollee['name'].toString().trim();
        
        // Skip empty names or IDs
        if (name == "," || name.isEmpty || userId.isEmpty) continue;

        // Check if user already exists
        int existingIndex = updatedUsers.indexWhere((u) => u.id == userId);
        
        if (existingIndex != -1) {
          // Update existing user
          User existing = updatedUsers[existingIndex];
          updatedUsers[existingIndex] = User(
            id: userId,
            biometricId: userId,
            name: name,
            email: name, // user said name is username
            password: userId, // user said user_id is pass
            role: existing.role,
            attendanceRecords: existing.attendanceRecords,
          );
        } else {
          // Create new user
          updatedUsers.add(User(
            id: userId,
            biometricId: userId,
            name: name,
            email: name,
            password: userId,
            role: 'Employee',
            attendanceRecords: [],
          ));
        }
      }
      
      return updatedUsers;
    } catch (e) {
      return currentUsers;
    }
  }
}
