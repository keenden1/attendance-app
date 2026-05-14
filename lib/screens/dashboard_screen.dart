import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/attendance.dart';
import '../services/json_storage_service.dart';
import 'biometric_raw_screen.dart';
import 'biometric_records_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  final User user;
  const DashboardScreen({super.key, required this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late User _currentUser;
  final _storageService = JsonStorageService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  Future<void> _importEnrollees() async {
    final TextEditingController jsonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Enrollees'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste the raw enrollees JSON content below:'),
            const Text(
              'Username will be the Name, Password will be the User ID.',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: jsonController,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"device_ip": "...", "enrollees": [...]}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final content = jsonController.text.trim();
              if (content.isNotEmpty) {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                setState(() => _isLoading = true);
                try {
                  await _storageService.importEnrolleesData(content);
                  
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Enrollees imported successfully!')),
                  );
                  setState(() => _isLoading = false);
                } catch (e) {
                  setState(() => _isLoading = false);
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('Error importing enrollees: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Import Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncBiometricData() async {
    final TextEditingController jsonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Biometric Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paste the raw biometric JSON content below to update employee logs:'),
            const SizedBox(height: 16),
            TextField(
              controller: jsonController,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"device_id": 5, "logs": [...]}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final content = jsonController.text.trim();
              if (content.isNotEmpty) {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                setState(() => _isLoading = true);
                try {
                  await _storageService.importBiometricData(content);
                  
                  // Refresh current user data
                  final allUsers = await _storageService.getUsers();
                  setState(() {
                    _currentUser = allUsers.firstWhere((u) => u.id == _currentUser.id);
                    _isLoading = false;
                  });

                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text('Biometric data synced successfully!')),
                  );
                } catch (e) {
                  setState(() => _isLoading = false);
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('Error syncing data: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Sync Now'),
          ),
        ],
      ),
    );
  }

  Attendance? get _todayRecord {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      return _currentUser.attendanceRecords.firstWhere((r) => r.date == todayStr);
    } catch (e) {
      return null;
    }
  }

  Future<void> _handleAttendance() async {
    setState(() => _isLoading = true);
    
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm').format(now);
    
    List<User> allUsers = await _storageService.getUsers();
    int userIndex = allUsers.indexWhere((u) => u.id == _currentUser.id);
    
    if (userIndex != -1) {
      User user = allUsers[userIndex];
      List<Attendance> records = List.from(user.attendanceRecords);
      
      Attendance? today = _todayRecord;
      
      if (today == null) {
        records.add(Attendance(
          date: dateStr,
          status: now.hour >= 9 && now.minute > 0 ? 'late' : 'present',
          checkInTime: timeStr,
        ));
      } else if (today.checkOutTime == null) {
        int recordIndex = records.indexWhere((r) => r.date == dateStr);
        records[recordIndex] = Attendance(
          date: today.date,
          status: today.status,
          checkInTime: today.checkInTime,
          checkOutTime: timeStr,
        );
      }
      
      User updatedUser = User(
        id: user.id,
        biometricId: user.biometricId,
        name: user.name,
        email: user.email,
        password: user.password,
        role: user.role,
        attendanceRecords: records,
      );
      
      allUsers[userIndex] = updatedUser;
      await _storageService.saveUsers(allUsers);
      
      setState(() {
        _currentUser = updatedUser;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = _todayRecord;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_currentUser.role == 'Admin') ...[
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.table_view),
              tooltip: 'View Raw Biometric Data',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BiometricRawScreen()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Import Enrollees',
              onPressed: _isLoading ? null : _importEnrollees,
            ),
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync Biometric Data',
              onPressed: _isLoading ? null : _syncBiometricData,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${_currentUser.name}',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Role: ${_currentUser.role} | ID: ${_currentUser.id}',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            
            Row(
              children: [
                _buildStatCard('Present', _currentUser.attendanceRecords.where((r) => r.status == 'present').length.toString(), Colors.green, Icons.check_circle_outline),
                const SizedBox(width: 12),
                _buildStatCard('Late', _currentUser.attendanceRecords.where((r) => r.status == 'late').length.toString(), Colors.orange, Icons.access_time),
                const SizedBox(width: 12),
                _buildStatCard('Absent', '0', Colors.red, Icons.cancel_outlined),
              ],
            ),
            const SizedBox(height: 24),
            
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Today\'s Status', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            Text(DateFormat('EEEE, MMM d').format(DateTime.now()), style: theme.textTheme.bodySmall),
                          ],
                        ),
                        _buildStatusBadge(today?.status),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildTimeInfo('Check In', today?.checkInTime ?? '--:--'),
                        _buildTimeInfo('Check Out', today?.checkOutTime ?? '--:--'),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading || (today != null && today.checkOutTime != null) ? null : _handleAttendance,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(today == null ? 'Check In' : 'Check Out'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8EAF6),
                  child: Icon(Icons.fingerprint, color: Color(0xFF1A237E)),
                ),
                title: const Text('My Biometric Records',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('View your raw attendance logs by date'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BiometricRecordsScreen(user: _currentUser),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Recent Activity', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _currentUser.attendanceRecords.isEmpty 
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No attendance records found.')))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _currentUser.attendanceRecords.length,
                  itemBuilder: (context, index) {
                    final record = _currentUser.attendanceRecords.reversed.toList()[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(record.status).withAlpha(25),
                          child: Icon(Icons.calendar_today, size: 18, color: _getStatusColor(record.status)),
                        ),
                        title: Text(record.date),
                        subtitle: Text('In: ${record.checkInTime ?? '-'} | Out: ${record.checkOutTime ?? '-'}'),
                        trailing: _buildStatusBadge(record.status),
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeInfo(String label, String time) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(time, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        (status ?? 'N/A').toUpperCase(),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'present': return Colors.green;
      case 'late': return Colors.orange;
      case 'absent': return Colors.red;
      default: return Colors.grey;
    }
  }
}
