/// รายการบำรุงรักษาและรอบเวลาเริ่มต้น
/// ค่าเริ่มต้นเป็นเพียงค่าโดยประมาณทั่วไป ให้ปรับตามคู่มือรถของคุณ (0 = ไม่กำหนด)
class ServiceType {
  const ServiceType(this.id, this.name, this.km, this.months);

  final String id;
  final String name;
  final int km;
  final int months;

  bool get scheduled => km > 0 || months > 0;
}

const List<ServiceType> kServiceTypes = [
  ServiceType('engine_oil', 'น้ำมันเครื่อง + กรองน้ำมันเครื่อง', 10000, 6),
  ServiceType('air_filter', 'กรองอากาศ', 20000, 12),
  ServiceType('cabin_filter', 'กรองแอร์', 20000, 12),
  ServiceType('fuel_filter', 'กรองน้ำมันเชื้อเพลิง', 40000, 24),
  ServiceType('brake_fluid', 'น้ำมันเบรก', 40000, 24),
  ServiceType('coolant', 'น้ำยาหล่อเย็น', 40000, 24),
  ServiceType('gear_oil', 'น้ำมันเกียร์ / เฟืองท้าย', 40000, 24),
  ServiceType('spark_plug', 'หัวเทียน', 40000, 48),
  ServiceType('belt', 'สายพาน', 60000, 48),
  ServiceType('brake_pad', 'ผ้าเบรก', 40000, 0),
  ServiceType('tire_rotate', 'สลับยาง', 10000, 6),
  ServiceType('tire_replace', 'เปลี่ยนยาง', 50000, 60),
  ServiceType('battery', 'แบตเตอรี่', 0, 24),
  ServiceType('other', 'อื่นๆ', 0, 0),
];

ServiceType serviceTypeOf(String id) =>
    kServiceTypes.firstWhere((t) => t.id == id, orElse: () => kServiceTypes.last);

class MaintenanceRecord {
  MaintenanceRecord({
    required this.id,
    required this.vehicleKey,
    required this.typeId,
    required this.date,
    required this.km,
    this.cost,
    this.note = '',
  });

  final String id;
  final String vehicleKey;
  final String typeId;
  final DateTime date;
  final int km;
  final int? cost;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'v': vehicleKey,
        't': typeId,
        'd': DateTime(date.year, date.month, date.day).toIso8601String(),
        'km': km,
        'cost': cost,
        'note': note,
      };

  static MaintenanceRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = DateTime.tryParse('${j['d']}');
    final km = j['km'];
    if (d == null || km is! int || j['id'] == null || j['v'] == null || j['t'] == null) return null;
    final cost = j['cost'];
    return MaintenanceRecord(
      id: '${j['id']}',
      vehicleKey: '${j['v']}',
      typeId: '${j['t']}',
      date: d,
      km: km,
      cost: cost is int ? cost : null,
      note: '${j['note'] ?? ''}',
    );
  }
}

enum DueLevel { none, ok, soon, overdue }

class DueStatus {
  const DueStatus(this.level, this.text);

  final DueLevel level;
  final String text;
}

String fmtNum(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

const List<String> _thMonths = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

/// รูปแบบวันที่ เช่น 23 ต.ค. 2026 (ค.ศ. ให้ตรงกับตัวเลือกวันที่ของระบบ)
String fmtDate(DateTime d) => '${d.day} ${_thMonths[d.month - 1]} ${d.year}';

DateTime addMonths(DateTime d, int months) => DateTime(d.year, d.month + months, d.day);

/// คำนวณสถานะถึงกำหนด จากบันทึกล่าสุดของรายการนั้น
/// [km] และ [months] คือรอบที่ใช้ (0 = ไม่กำหนด) [currentKm] คือเลขไมล์ปัจจุบันที่ผู้ใช้กรอก
DueStatus computeDue({
  required int km,
  required int months,
  required MaintenanceRecord? last,
  required int? currentKm,
  required DateTime today,
}) {
  if (km <= 0 && months <= 0) return const DueStatus(DueLevel.none, 'ไม่ได้ตั้งรอบ');
  if (last == null) return const DueStatus(DueLevel.none, 'ยังไม่มีบันทึก');

  final parts = <String>[];
  var level = DueLevel.ok;

  void raise(DueLevel l) {
    if (l.index > level.index) level = l;
  }

  if (km > 0 && currentKm != null) {
    final left = last.km + km - currentKm;
    if (left < 0) {
      parts.add('เกินมา ${fmtNum(-left)} กม.');
      raise(DueLevel.overdue);
    } else {
      parts.add('อีก ${fmtNum(left)} กม.');
      if (left <= 1000) raise(DueLevel.soon);
    }
  }

  if (months > 0) {
    final due = addMonths(last.date, months);
    final t = DateTime(today.year, today.month, today.day);
    final days = due.difference(t).inDays;
    if (days < 0) {
      parts.add('เกินมา ${-days} วัน');
      raise(DueLevel.overdue);
    } else {
      parts.add('อีก $days วัน');
      if (days <= 30) raise(DueLevel.soon);
    }
  }

  if (parts.isEmpty) return const DueStatus(DueLevel.none, 'ใส่เลขไมล์ปัจจุบันเพื่อคำนวณ');
  return DueStatus(level, parts.join(' / '));
}
