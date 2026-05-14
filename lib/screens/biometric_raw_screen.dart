import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/supabase_service.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class BiometricRawScreen extends StatefulWidget {
  final String? biometricId;
  const BiometricRawScreen({super.key, this.biometricId});

  @override
  State<BiometricRawScreen> createState() => _BiometricRawScreenState();
}

class _BiometricRawScreenState extends State<BiometricRawScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  Map<String, dynamic>? _deviceInfo;
  List<Map<String, dynamic>> _enrollees = [];
  List<Map<String, dynamic>> _attendance = [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _lastSyncTime;
  bool _configured = true;

  // Pagination for Employee View
  int _visibleGroups = 10;
  final int _groupIncrement = 10;

  // For search/filter
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isAdmin => widget.biometricId == null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isAdmin ? 2 : 1, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
    _fetchFromSupabase();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFromSupabase() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = await SupabaseService.build();

      if (service == null) {
        setState(() {
          _isLoading = false;
          _configured = false;
        });
        return;
      }
      
      // Admin sees ALL data files to manage them; Employees see only the ACTIVE file
      final data = await service.fetchAllData(forceAll: _isAdmin);
      final rawEnrollees = data['enrollees'] as List? ?? [];
      List<Map<String, dynamic>> rawAttendance = (data['attendance'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // Extract the fetch_time from the JSON response
      String? jsonFetchTime = data['fetch_time']?.toString();
      if (jsonFetchTime != null) {
        try {
          // Converts "2026-05-06 16:09:30" to "May 6, 04:09 PM"
          final dt = DateTime.parse(jsonFetchTime);
          _lastSyncTime = DateFormat('MMM d, hh:mm a').format(dt);
        } catch (_) {
          _lastSyncTime = jsonFetchTime; // fallback to raw string
        }
      } else {
        _lastSyncTime = DateFormat('MMM d, hh:mm a').format(DateTime.now());
      }

      // Filter by biometricId if provided (only show logs for the logged-in user)
      if (widget.biometricId != null) {
        rawAttendance = rawAttendance
            .where((log) => log['id']?.toString() == widget.biometricId)
            .toList();
      }

      // Sort by timestamp descending (latest on top)
      rawAttendance.sort((a, b) {
        final aTs = a['timestamp']?.toString() ?? '';
        final bTs = b['timestamp']?.toString() ?? '';
        return bTs.compareTo(aTs);
      });

      setState(() {
        _deviceInfo = {
          'device_ip': 'Supabase Storage',
          'device_port': service.bucket,
          'fetch_time': 'Latest Sync',
          'total_enrollees': rawEnrollees.length,
          'total_attendance': rawAttendance.length,
        };
        _enrollees = rawEnrollees.cast<Map<String, dynamic>>();
        _attendance = rawAttendance;
        _isLoading = false;
        _errorMessage = null;
        _configured = true;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to fetch from Supabase: $e';
      });
    }
  }

  Future<void> _showActiveFilePicker() async {
    setState(() => _isLoading = true);
    try {
      final service = await SupabaseService.build();
      if (service == null) return;

      final allFiles = (await service.listFiles())
          .where((f) => f != 'app_config.json')
          .toList();
      
      final config = await service.getConfig();
      final currentActive = config?['active_file']?.toString();

      if (!mounted) return;
      setState(() => _isLoading = false);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Set Employee View'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('Select which JSON file employees should see:', 
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Show All Files (Default)', style: TextStyle(fontWeight: FontWeight.bold)),
                  leading: Icon(Icons.all_inclusive_rounded, color: currentActive == null ? Colors.blue : Colors.grey),
                  onTap: () async {
                    Navigator.pop(context);
                    await _setActiveFile(null);
                  },
                ),
                const Divider(),
                ...allFiles.map((file) => ListTile(
                  title: Text(file, style: const TextStyle(fontSize: 14)),
                  leading: Icon(Icons.insert_drive_file_rounded, 
                      color: currentActive == file ? Colors.blue : Colors.grey),
                  trailing: currentActive == file ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                  onTap: () async {
                    Navigator.pop(context);
                    await _setActiveFile(file);
                  },
                )),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _setActiveFile(String? filename) async {
    setState(() => _isLoading = true);
    try {
      final service = await SupabaseService.build();
      if (service != null) {
        await service.setConfig({'active_file': filename ?? ''});
        await _fetchFromSupabase();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(filename == null ? 'Employees can now see all files.' : 'Employees are now limited to: $filename')),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update config: $e')));
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await SupabaseService.clearUserSession();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredEnrollees {
    if (_searchQuery.isEmpty) return _enrollees;
    return _enrollees.where((e) {
      return e.values.any((v) => v.toString().toLowerCase().contains(_searchQuery));
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredAttendance {
    if (_searchQuery.isEmpty) return _attendance;
    return _attendance.where((e) {
      // Check all raw values
      final matchesRaw = e.values.any((v) => v.toString().toLowerCase().contains(_searchQuery));
      if (matchesRaw) return true;

      // Also check the formatted date string (e.g., "May 1, 2026")
      final timestamp = e['timestamp']?.toString();
      if (timestamp != null) {
        try {
          final dt = DateTime.parse(timestamp);
          final formattedDate = DateFormat('MMMM d, yyyy').format(dt).toLowerCase();
          if (formattedDate.contains(_searchQuery)) return true;
        } catch (_) {}
      }

      return false;
    }).toList();
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_isAdmin ? 'Admin Dashboard' : 'My Attendance'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.settings_applications_rounded),
              tooltip: 'Set Active File',
              onPressed: _showActiveFilePicker,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchFromSupabase,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
        bottom: _deviceInfo != null && _isAdmin
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'Enrollees (${_enrollees.length})'),
                  Tab(text: 'Attendance (${_attendance.length})'),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_configured
              ? _buildNotConfigured(theme)
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchFromSupabase,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _deviceInfo == null
                      ? _buildEmptyState(theme)
                      : Column(
                          children: [
                            _buildDeviceInfoCard(),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Search…',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () => _searchController.clear(),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            Expanded(
                              child: _isAdmin 
                                ? TabBarView(
                                    controller: _tabController,
                                    children: [
                                      _buildEnrolleesTab(),
                                      _buildAttendanceTab(),
                                    ],
                                  )
                                : _buildAttendanceTab(),
                            ),
                          ],
                        ),
    );
  }

  Widget _buildNotConfigured(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Supabase not configured',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
              },
              child: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fingerprint, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No data found in Supabase',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey[500])),
          const SizedBox(height: 8),
          Text('Ensure your JSON files are in the configured bucket.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[400])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchFromSupabase,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh Data'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    if (_deviceInfo == null) return const SizedBox.shrink();
    
    final info = _deviceInfo!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sync_rounded, size: 16, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAdmin 
                    ? '${info['device_ip']} · ${info['device_port']}'
                    : 'Records Synced',
                  style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                if (_lastSyncTime != null)
                  Text(
                    'Last resync: $_lastSyncTime',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          if (_isAdmin)
            Text(
              '${info['total_enrollees']} enrollees · ${info['total_attendance']} logs',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildEnrolleesTab() {
    const cols = ['uid', 'user_id', 'name', 'privilege', 'group_id', 'card'];
    final rows = _filteredEnrollees;

    if (rows.isEmpty) {
      return const Center(child: Text('No enrollees found.'));
    }

    return _RawDataTable(columns: cols, rows: rows);
  }

  Widget _buildAttendanceTab() {
    if (_filteredAttendance.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('No attendance records found.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_isAdmin) {
      final rows = _filteredAttendance.map((row) {
        final formattedRow = Map<String, dynamic>.from(row);
        final rawTs = row['timestamp']?.toString();
        if (rawTs != null) {
          try {
            final dt = DateTime.parse(rawTs);
            formattedRow['timestamp'] = DateFormat('EEEE, MMM d, yyyy · hh:mm a').format(dt);
          } catch (_) {}
        }
        return formattedRow;
      }).toList();
      const cols = ['uid', 'id', 'timestamp', 'state', 'type'];
      return _RawDataTable(columns: cols, rows: rows);
    }

    // Group by Date for Employee View
    final Map<String, List<DateTime>> grouped = {};
    for (final record in _filteredAttendance) {
      final rawTs = record['timestamp']?.toString();
      if (rawTs != null) {
        try {
          final dt = DateTime.parse(rawTs);
          final dateKey = DateFormat('EEEE, MMMM d, yyyy').format(dt);
          grouped.putIfAbsent(dateKey, () => []).add(dt);
        } catch (_) {}
      }
    }

    // Sort times within each date (earliest first: AM to PM)
    for (final dateKey in grouped.keys) {
      grouped[dateKey]!.sort((a, b) => a.compareTo(b));
    }

    final dateKeys = grouped.keys.toList();
    final displayedKeys = dateKeys.take(_visibleGroups).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemCount: displayedKeys.length + (dateKeys.length > _visibleGroups ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == displayedKeys.length) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: OutlinedButton(
              onPressed: () => setState(() => _visibleGroups += _groupIncrement),
              child: const Text('Load More Records'),
            ),
          );
        }

        final date = displayedKeys[index];
        final times = grouped[date]!;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            backgroundColor: Colors.white,
            collapsedBackgroundColor: Colors.white,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.calendar_today_rounded, 
                  color: Theme.of(context).colorScheme.primary, size: 20),
            ),
            title: Text(
              date,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              '${times.length} record${times.length > 1 ? 's' : ''}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            children: times.map((dt) {
              final timeStr = DateFormat('hh:mm a').format(dt);
              return Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade50)),
                ),
                child: ListTile(
                  dense: true,
                  leading: const SizedBox(width: 40), // indent
                  title: Text(
                    timeStr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  trailing: const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _RawDataTable extends StatelessWidget {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;

  const _RawDataTable({required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
          ),
          child: PaginatedDataTable(
            header: null,
            rowsPerPage: rows.length < 10 ? (rows.isEmpty ? 1 : rows.length) : 10,
            availableRowsPerPage: const [10, 25, 50],
            showFirstLastButtons: true,
            columnSpacing: 24,
            horizontalMargin: 20,
            headingRowHeight: 56,
            dataRowMaxHeight: 56,
            columns: columns
                .map((c) => DataColumn(
                      label: Text(
                        c.replaceAll('_', ' ').toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ))
                .toList(),
            source: _GenericDataSource(rows: rows, columns: columns),
          ),
        ),
      ),
    );
  }
}

class _GenericDataSource extends DataTableSource {
  final List<Map<String, dynamic>> rows;
  final List<String> columns;

  _GenericDataSource({required this.rows, required this.columns});

  @override
  DataRow? getRow(int index) {
    if (index >= rows.length) return null;
    final row = rows[index];
    final isEven = index % 2 == 0;

    return DataRow.byIndex(
      index: index,
      color: WidgetStateProperty.all(isEven ? Colors.white : const Color(0xFFFBFBFF)),
      cells: columns.map((c) {
        final val = row[c]?.toString() ?? '-';
        return DataCell(
          Text(
            val,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[800],
              fontWeight: c == 'timestamp' ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rows.length;

  @override
  int get selectedRowCount => 0;
}


