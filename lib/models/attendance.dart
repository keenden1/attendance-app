class Attendance {
  final String date;
  final String status; // present, late, amber, absent
  final String? checkInTime;
  final String? checkOutTime;

  Attendance({
    required this.date,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'status': status,
      'checkInTime': checkInTime,
      'checkOutTime': checkOutTime,
    };
  }

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      date: json['date'],
      status: json['status'],
      checkInTime: json['checkInTime'],
      checkOutTime: json['checkOutTime'],
    );
  }
}
