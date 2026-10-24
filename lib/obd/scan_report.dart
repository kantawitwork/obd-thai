/// ผลการอ่านโค้ดหนึ่งชุด (เช่น โค้ดที่ค้างอยู่ หรือโค้ดที่ยังไม่ยืนยัน)
class DtcResult {
  const DtcResult({required this.codes, required this.answered});

  /// รหัสโค้ดที่พบ (ว่างได้)
  final List<String> codes;

  /// รถตอบกลับคำสั่งนี้หรือไม่ false = ไม่รองรับหรือไม่ตอบ (ไม่ใช่ "ไม่มีโค้ด")
  final bool answered;
}

/// สถานะของระบบตรวจสอบหนึ่งรายการ (Readiness monitor)
enum MonitorState { ready, notReady, unsupported }

class Monitor {
  const Monitor(this.name, this.state);

  final String name;
  final MonitorState state;
}

/// ข้อมูลจาก Mode 01 PID 01
class VehicleStatus {
  const VehicleStatus({
    required this.milOn,
    required this.dtcCount,
    required this.isDiesel,
    required this.monitors,
  });

  final bool milOn;
  final int dtcCount;
  final bool isDiesel;
  final List<Monitor> monitors;

  int get supportedCount => monitors.where((m) => m.state != MonitorState.unsupported).length;
  int get readyCount => monitors.where((m) => m.state == MonitorState.ready).length;

  /// แปลง 4 ไบต์ A B C D ของคำตอบ 41 01 เป็นสถานะ
  static VehicleStatus fromBytes(List<int> d) {
    final a = d[0], b = d[1], c = d[2], e = d[3];
    final diesel = (b & 0x08) != 0;

    MonitorState st(bool supported, bool incomplete) =>
        !supported ? MonitorState.unsupported : (incomplete ? MonitorState.notReady : MonitorState.ready);

    final monitors = <Monitor>[
      // ระบบที่ตรวจตลอดเวลา (บิต 0-2 = รองรับ, บิต 4-6 = ยังไม่เสร็จ)
      Monitor('ตรวจจับไฟแตกผิดจังหวะ', st(b & 0x01 != 0, b & 0x10 != 0)),
      Monitor('ระบบเชื้อเพลิง', st(b & 0x02 != 0, b & 0x20 != 0)),
      Monitor('ชิ้นส่วนที่เกี่ยวข้องกับไอเสีย', st(b & 0x04 != 0, b & 0x40 != 0)),
    ];

    bool sup(int bit) => c & (1 << bit) != 0;
    bool inc(int bit) => e & (1 << bit) != 0;

    if (!diesel) {
      const names = [
        'ตัวเร่งปฏิกิริยา (แคทาไลติก)',
        'ตัวเร่งปฏิกิริยาแบบอุ่น',
        'ระบบไอระเหยน้ำมัน (EVAP)',
        'ระบบอากาศเสริมไอเสีย',
        'น้ำยาแอร์',
        'ออกซิเจนเซนเซอร์',
        'ฮีตเตอร์ออกซิเจนเซนเซอร์',
        'ระบบหมุนเวียนไอเสีย (EGR)',
      ];
      for (var i = 0; i < names.length; i++) {
        monitors.add(Monitor(names[i], st(sup(i), inc(i))));
      }
    } else {
      // เครื่องดีเซล: บิต 2 และ 4 ไม่ได้ใช้
      const names = {
        0: 'ตัวเร่งปฏิกิริยา NMHC',
        1: 'ระบบลด NOx / SCR',
        3: 'ความดันเทอร์โบ',
        5: 'เซนเซอร์ก๊าซไอเสีย',
        6: 'กรองอนุภาค (DPF)',
        7: 'ระบบหมุนเวียนไอเสีย (EGR/VVT)',
      };
      names.forEach((bit, name) => monitors.add(Monitor(name, st(sup(bit), inc(bit)))));
    }

    return VehicleStatus(
      milOn: a & 0x80 != 0,
      dtcCount: a & 0x7F,
      isDiesel: diesel,
      monitors: monitors,
    );
  }
}

/// ข้อมูลรถและกล่อง ECU ที่อ่านได้ (ช่องที่รถไม่ตอบจะเป็น null หรือว่าง)
class VehicleInfo {
  const VehicleInfo({
    this.vin,
    this.calibrationIds = const [],
    this.ecuNames = const [],
    this.ecuSerial,
    this.partNumber,
    this.softwareVersion,
    this.kmWithMil,
    this.kmSinceCleared,
    this.minutesSinceCleared,
  });

  /// ระยะทางที่ขับขณะไฟเตือนเครื่องยนต์ติด (กม.) ไม่ใช่เลขไมล์รวมของรถ
  final int? kmWithMil;

  /// ระยะทางที่ขับตั้งแต่ล้างโค้ดครั้งล่าสุด (กม.) ไม่ใช่เลขไมล์รวมของรถ
  final int? kmSinceCleared;

  /// เวลาที่เครื่องยนต์ทำงานตั้งแต่ล้างโค้ดครั้งล่าสุด (นาที)
  final int? minutesSinceCleared;

  /// เลขตัวถัง (Mode 09 หรือ UDS F190)
  final String? vin;

  /// รหัสซอฟต์แวร์ของ ECU (Mode 09 PID 04)
  final List<String> calibrationIds;

  /// ชื่อ ECU (Mode 09 PID 0A)
  final List<String> ecuNames;

  /// เลขซีเรียลของกล่อง ECU (UDS F18C) ไม่ใช่เลขเครื่องยนต์
  final String? ecuSerial;

  /// เลขชิ้นส่วนของ ECU (UDS F187)
  final String? partNumber;

  /// เวอร์ชันซอฟต์แวร์ (UDS F189)
  final String? softwareVersion;

  bool get isEmpty =>
      vin == null &&
      calibrationIds.isEmpty &&
      ecuNames.isEmpty &&
      ecuSerial == null &&
      partNumber == null &&
      softwareVersion == null &&
      kmWithMil == null &&
      kmSinceCleared == null &&
      minutesSinceCleared == null;
}

/// รายงานรวมจากการสแกนหนึ่งครั้ง
class ScanReport {
  const ScanReport({
    required this.time,
    required this.stored,
    required this.pending,
    required this.permanent,
    required this.status,
    required this.vin,
  });

  final DateTime time;
  final DtcResult stored;
  final DtcResult pending;
  final DtcResult permanent;

  /// null = อ่านสถานะไม่ได้
  final VehicleStatus? status;
  final String? vin;

  /// โค้ดทั้งหมดที่พบ (ไม่ซ้ำ)
  List<String> get allCodes => {...stored.codes, ...pending.codes, ...permanent.codes}.toList();

  bool get hasAnyCode => allCodes.isNotEmpty;
}
