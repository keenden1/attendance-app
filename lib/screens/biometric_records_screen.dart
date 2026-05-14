import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user.dart';
import '../services/supabase_service.dart';


class BiometricRecordsScreen extends StatefulWidget {
  final User user;
  const BiometricRecordsScreen({super.key, required this.user});

  @override
  State<BiometricRecordsScreen> createState() => _BiometricRecordsScreenState();
}

class _BiometricRecordsScreenState extends State<BiometricRecordsScreen> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _configured = false;

  static const _cols = ['uid', 'id', 'timestamp', 'state', 'type'];

  @override
  void initState() {
    super.initState();
    _checkConfigAndFetch();
  }

  Future<void> _checkConfigAndFetch() async {
    final service = await SupabaseService.build();
    if (service == null) {
      setState(() => _configured = false);
      return;
    }
    setState(() => _configured = true);
    await _fetch(service);
  }

  Future<void> _fetch(SupabaseService service) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _records = [];
    });

    try {
      final data = await service.fetchAllData();
      final List<Map<String, dynamic>> all = (data['attendance'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final biometricId = widget.user.biometricId ?? widget.user.id;
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final filtered = all.where((entry) {
        final matchesId = entry['id']?.toString() == biometricId;
        final ts = entry['timestamp']?.toString() ?? '';
        final matchesDate = ts.startsWith(dateStr);
        return matchesId && matchesDate;
      }).toList();

      // Sort by timestamp ascending
      filtered.sort((a, b) =>
          (a['timestamp'] ?? '').toString().compareTo(
              (b['timestamp'] ?? '').toString()));

      setState(() {
        _records = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      final service = await SupabaseService.build();
      if (service != null) await _fetch(service);
    }
  }

  Future<void> _refresh() async {
    final service = await SupabaseService.build();
    if (service != null) await _fetch(service);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEEE, MMM d, yyyy').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Biometric Records'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_configured)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _isLoading ? null : _refresh,
            ),
        ],
      ),
      body: !_configured
          ? _buildNotConfigured(theme)
          : Column(
              children: [
                _buildDateBar(dateLabel, theme),
                Expanded(child: _buildBody(theme)),
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
            const SizedBox(height: 8),
            Text(
              'Ask your administrator to configure the Supabase connection in Settings.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateBar(String dateLabel, ThemeData theme) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 18, color: Color(0xFF1A237E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(dateLabel,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: _isLoading ? null : _pickDate,
            child: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Fetching records from Supabase…',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fingerprint, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No records found for this date.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(const Color(0xFF1A237E)),
            headingTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13),
            dataRowMinHeight: 36,
            dataRowMaxHeight: 48,
            columnSpacing: 24,
            border: TableBorder.all(color: Colors.grey.shade200, width: 1),
            columns: _cols
                .map((c) => DataColumn(
                    label: Text(c.replaceAll('_', ' ').toUpperCase())))
                .toList(),
            rows: _records.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              return DataRow(
                color: WidgetStateProperty.all(
                  i % 2 == 0 ? Colors.white : const Color(0xFFF8F9FF),
                ),
                cells: _cols
                    .map((c) => DataCell(Text(
                          row[c]?.toString() ?? '-',
                          style: const TextStyle(fontSize: 13),
                        )))
                    .toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
