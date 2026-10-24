import 'dart:async';

import 'scan_report.dart';
import 'transport.dart';

class ObdException implements Exception {
  ObdException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LiveData {
  const LiveData({this.rpm, this.speed, this.coolant, this.throttle, this.voltage});
  final double? rpm;
  final double? speed;
  final double? coolant;
  final double? throttle;
  final double? voltage;
}

/// ตัวสื่อสารกับชิป ELM327 ผ่านชุดคำสั่ง AT และคำสั่ง OBD2 มาตรฐาน (SAE J1979)
class Elm327 {
  Elm327(this._transport);

  final ObdTransport _transport;
  final StringBuffer _buf = StringBuffer();
  StreamSubscription<List<int>>? _sub;
  Completer<String>? _waiting;
  Future<void> _tail = Future<void>.value();

  /// รถใช้ CAN หรือไม่ (มีผลต่อรูปแบบคำตอบของ Mode 03)
  bool isCan = true;
  String protocolName = '';

  // ---------------------------------------------------------------- เชื่อมต่อ

  Future<void> open() async {
    await _transport.connect();
    _sub = _transport.incoming.listen(_onData);

    await send('ATZ', timeout: const Duration(seconds: 6)); // รีเซ็ตเครื่อง
    await send('ATE0'); // ปิด echo
    await send('ATL0'); // ปิดขึ้นบรรทัดใหม่เพิ่ม
    await send('ATH0'); // ไม่แสดง header
    await send('ATSP0'); // ตรวจโปรโตคอลอัตโนมัติ

    // การสั่ง 0100 ครั้งแรกทำให้เครื่องค้นหาโปรโตคอลของรถ อาจใช้เวลาหลายวินาที
    final r = await send('0100', timeout: const Duration(seconds: 15));
    final ok = messages(r).any((m) => m.length >= 2 && m[0] == 0x41 && m[1] == 0x00);
    if (!ok) {
      throw ObdException('ต่อกับเครื่อง OBD2 ได้ แต่รถไม่ตอบกลับ ลองเปิดกุญแจเป็น ON แล้วเชื่อมต่อใหม่');
    }

    final n = await send('ATDPN');
    final id = n.isEmpty ? '' : n.first.trim().toUpperCase();
    final last = id.isEmpty ? '' : id[id.length - 1];
    isCan = last.isEmpty || '6789ABC'.contains(last);

    final p = await send('ATDP');
    protocolName = p.isEmpty ? '' : p.first.replaceFirst(RegExp(r'^AUTO,\s*'), '');
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _transport.disconnect();
    } catch (_) {}
  }

  // -------------------------------------------------------------- ส่งคำสั่ง

  void _onData(List<int> data) {
    _buf.write(String.fromCharCodes(data));
    final text = _buf.toString();
    // ELM327 ตอบจบด้วยเครื่องหมาย '>' เสมอ
    if (text.contains('>')) {
      final w = _waiting;
      _waiting = null;
      _buf.clear();
      if (w != null && !w.isCompleted) w.complete(text);
    }
  }

  /// ส่งคำสั่งทีละคำสั่งตามลำดับ (กันคำสั่งชนกันเมื่อมีหลายหน้าจอใช้พร้อมกัน)
  Future<List<String>> send(String cmd, {Duration timeout = const Duration(seconds: 5)}) {
    final c = Completer<List<String>>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await _sendNow(cmd, timeout));
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }

  Future<List<String>> _sendNow(String cmd, Duration timeout) async {
    _buf.clear();
    final waiting = Completer<String>();
    _waiting = waiting;
    await _transport.write('$cmd\r'.codeUnits);

    String raw;
    try {
      raw = await waiting.future.timeout(timeout);
    } on TimeoutException {
      _waiting = null;
      throw ObdException('เครื่อง OBD2 ไม่ตอบสนอง (คำสั่ง $cmd)');
    }

    final lines = raw
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.replaceAll('>', '').trim())
        .where((l) => l.isNotEmpty && l != cmd && !l.startsWith('SEARCHING'))
        .toList();

    if (lines.any((l) => l.contains('UNABLE TO CONNECT'))) {
      throw ObdException('เครื่องต่อกับรถไม่ได้ ตรวจสอบว่าเปิดกุญแจเป็น ON แล้ว');
    }
    if (lines.any((l) => l.contains('CAN ERROR'))) {
      throw ObdException('เกิดข้อผิดพลาดบนสายสื่อสาร CAN ลองเชื่อมต่อใหม่');
    }
    return lines;
  }

  // ------------------------------------------------------------ แยกข้อมูล

  static List<int> _toBytes(String text) {
    final s = text.replaceAll(RegExp(r'\s+'), '');
    final out = <int>[];
    for (var i = 0; i + 1 < s.length; i += 2) {
      final v = int.tryParse(s.substring(i, i + 2), radix: 16);
      if (v != null) out.add(v);
    }
    return out;
  }

  /// แปลงบรรทัดคำตอบเป็นข้อความ (list ของไบต์) รองรับคำตอบหลายเฟรมแบบ "0: ... 1: ..."
  static List<List<int>> messages(List<String> lines) {
    final out = <List<int>>[];
    List<int>? cur;
    final prefixed = RegExp(r'^([0-9A-F]):\s*(.*)$');
    final lengthOnly = RegExp(r'^[0-9A-F]{3}$');
    final hexOnly = RegExp(r'^[0-9A-F ]+$');

    for (final raw in lines) {
      final l = raw.trim().toUpperCase();
      if (l.isEmpty) continue;

      final m = prefixed.firstMatch(l);
      if (m != null) {
        if (m.group(1) == '0' || cur == null) {
          cur = <int>[];
          out.add(cur);
        }
        cur.addAll(_toBytes(m.group(2)!));
        continue;
      }
      if (lengthOnly.hasMatch(l)) continue; // บรรทัดบอกจำนวนไบต์ของคำตอบหลายเฟรม
      if (!hexOnly.hasMatch(l)) continue; // ข้อความอื่น เช่น NO DATA
      out.add(_toBytes(l));
      cur = null;
    }
    return out;
  }

  static String _decodeDtc(int a, int b) {
    const prefix = ['P', 'C', 'B', 'U'];
    final p = prefix[(a >> 6) & 0x3];
    final d1 = (a >> 4) & 0x3;
    final rest = '${(a & 0xF).toRadixString(16)}'
        '${(b >> 4).toRadixString(16)}'
        '${(b & 0xF).toRadixString(16)}';
    return '$p$d1$rest'.toUpperCase();
  }

  /// แปลงคำตอบ Mode 03/07/0A เป็นรหัสโค้ด เช่น P0301
  /// [header] คือไบต์แรกของคำตอบ: 0x43 (โหมด 03), 0x47 (โหมด 07), 0x4A (โหมด 0A)
  /// บน CAN คำตอบเป็น <header> <จำนวนโค้ด> <คู่ไบต์ DTC...>
  /// บนโปรโตคอลเก่า คำตอบเป็น <header> <คู่ไบต์ DTC...> เติม 00 00 ให้ครบ
  static List<String> parseDtcs(List<String> lines, {required bool isCan, int header = 0x43}) {
    final found = <String>[];
    for (final msg in messages(lines)) {
      if (msg.isEmpty || msg[0] != header) continue;
      for (var i = isCan ? 2 : 1; i + 1 < msg.length; i += 2) {
        final a = msg[i];
        final b = msg[i + 1];
        if (a == 0 && b == 0) continue;
        final code = _decodeDtc(a, b);
        if (!found.contains(code)) found.add(code);
      }
    }
    return found;
  }

  // ----------------------------------------------------------- คำสั่งใช้งาน

  /// Mode 03: อ่านโค้ดปัญหาที่ค้างอยู่
  Future<List<String>> readDtcs() async {
    final r = await send('03', timeout: const Duration(seconds: 10));
    return parseDtcs(r, isCan: isCan);
  }

  /// อ่านโค้ดตามโหมด (03 ค้างอยู่, 07 ยังไม่ยืนยัน, 0A ถาวร) พร้อมบอกว่ารถตอบหรือไม่
  /// ถ้าโหมดใดรถไม่รองรับ (NO DATA) จะได้ answered = false แทนที่จะถือว่า "ไม่มีโค้ด"
  Future<DtcResult> _readMode(String mode, int header) async {
    try {
      final r = await send(mode, timeout: const Duration(seconds: 10));
      final answered = messages(r).any((m) => m.isNotEmpty && m[0] == header);
      return DtcResult(codes: parseDtcs(r, isCan: isCan, header: header), answered: answered);
    } on ObdException {
      return const DtcResult(codes: [], answered: false);
    }
  }

  /// Mode 01 PID 01: ไฟเตือน MIL, จำนวนโค้ด และสถานะระบบตรวจสอบ (Readiness)
  Future<VehicleStatus?> readStatus() async {
    final bytes = await _pid('01');
    if (bytes == null || bytes.length < 4) return null;
    return VehicleStatus.fromBytes(bytes);
  }

  /// Mode 09 PID 02: เลขตัวถัง (VIN) หลายรุ่นไม่รองรับ จะได้ null
  Future<String?> readVin() async {
    try {
      final lines = await send('0902', timeout: const Duration(seconds: 8));
      final bytes = <int>[];
      for (final m in messages(lines)) {
        // คำตอบ: 49 02 <ลำดับ> <ข้อมูล 4 ไบต์ ...>
        if (m.length > 3 && m[0] == 0x49 && m[1] == 0x02) {
          bytes.addAll(m.sublist(3));
        } else if (m.length > 2 && m[0] == 0x49 && m[1] == 0x02) {
          bytes.addAll(m.sublist(2));
        }
      }
      final vin = String.fromCharCodes(bytes.where((b) => b >= 0x30 && b <= 0x5A))
          .replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (vin.length < 11) return null;
      return vin.length > 17 ? vin.substring(vin.length - 17) : vin;
    } on ObdException {
      return null;
    }
  }

  static String _printable(Iterable<int> bytes) =>
      String.fromCharCodes(bytes.where((x) => x >= 0x20 && x <= 0x7E)).trim();

  /// อ่านข้อความจาก Mode 09 (04 = รหัสซอฟต์แวร์, 0A = ชื่อ ECU)
  /// บน CAN แต่ละ ECU ตอบแยกกัน จึงได้ข้อความหลายรายการ
  Future<List<String>> _mode09Text(String pid) async {
    try {
      final lines = await send('09$pid', timeout: const Duration(seconds: 8));
      final want = int.parse(pid, radix: 16);
      final msgs = messages(lines)
          .where((m) => m.length > 3 && m[0] == 0x49 && m[1] == want)
          .toList();
      if (isCan) {
        return msgs.map((m) => _printable(m.sublist(3))).where((s) => s.isNotEmpty).toSet().toList();
      }
      final s = _printable(msgs.expand((m) => m.sublist(3)));
      return s.isEmpty ? <String>[] : [s];
    } on ObdException {
      return <String>[];
    }
  }

  /// UDS บริการ 22 (อ่านข้อมูลตามรหัส DID) รถหลายรุ่นไม่ตอบ จะได้ null
  /// F190 = VIN, F187 = เลขชิ้นส่วน, F189 = เวอร์ชันซอฟต์แวร์, F18C = ซีเรียลของกล่อง ECU
  Future<String?> _udsText(int did) async {
    try {
      final hex = did.toRadixString(16).toUpperCase().padLeft(4, '0');
      final lines = await send('22$hex', timeout: const Duration(seconds: 6));
      final hi = did >> 8;
      final lo = did & 0xFF;
      for (final m in messages(lines)) {
        if (m.length > 3 && m[0] == 0x62 && m[1] == hi && m[2] == lo) {
          final s = _printable(m.sublist(3));
          if (s.isNotEmpty) return s;
        }
      }
    } on ObdException {
      // รถไม่ตอบ ถือว่าไม่รองรับ
    }
    return null;
  }

  int? _u16(List<int>? b) => (b != null && b.length >= 2) ? b[0] * 256 + b[1] : null;

  /// อ่านข้อมูลรถและกล่อง ECU เท่าที่รถยอมตอบ (อ่านอย่างเดียว ไม่เขียนค่าใดๆ)
  Future<VehicleInfo> readVehicleInfo() async {
    var vin = await readVin();
    if (vin == null) {
      final u = await _udsText(0xF190);
      if (u != null) {
        final c = u.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (c.length >= 11) vin = c;
      }
    }

    final cal = await _mode09Text('04');
    final names = await _mode09Text('0A');
    final serial = await _udsText(0xF18C);
    final part = await _udsText(0xF187);
    final sw = await _udsText(0xF189);

    int? kmMil, kmCleared, minCleared;
    try {
      kmMil = _u16(await _pid('21'));
      kmCleared = _u16(await _pid('31'));
      minCleared = _u16(await _pid('4E'));
    } on ObdException {
      // ข้ามค่าที่อ่านไม่ได้
    }

    return VehicleInfo(
      vin: vin,
      calibrationIds: cal,
      ecuNames: names,
      ecuSerial: serial,
      partNumber: part,
      softwareVersion: sw,
      kmWithMil: kmMil,
      kmSinceCleared: kmCleared,
      minutesSinceCleared: minCleared,
    );
  }

  /// สแกนครบทุกอย่างในครั้งเดียว
  Future<ScanReport> fullScan() async {
    final stored = await _readMode('03', 0x43);
    final pending = await _readMode('07', 0x47);
    final permanent = await _readMode('0A', 0x4A);
    VehicleStatus? status;
    try {
      status = await readStatus();
    } on ObdException {
      status = null;
    }
    final vin = await readVin();
    return ScanReport(
      time: DateTime.now(),
      stored: stored,
      pending: pending,
      permanent: permanent,
      status: status,
      vin: vin,
    );
  }

  /// Mode 04: ล้างโค้ดและ Freeze frame (รถตอบ 44 เมื่อสำเร็จ)
  Future<bool> clearDtcs() async {
    final r = await send('04', timeout: const Duration(seconds: 10));
    return messages(r).any((m) => m.isNotEmpty && m[0] == 0x44);
  }

  Future<double?> readVoltage() async {
    final r = await send('ATRV');
    if (r.isEmpty) return null;
    final m = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(r.first);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  Future<List<int>?> _pid(String pid) async {
    final lines = await send('01$pid');
    final want = int.parse(pid, radix: 16);
    for (final m in messages(lines)) {
      if (m.length >= 2 && m[0] == 0x41 && m[1] == want) return m.sublist(2);
    }
    return null;
  }

  /// Mode 01: ข้อมูลสด (สูตรตามมาตรฐาน SAE J1979)
  Future<LiveData> readLive() async {
    final rpm = await _pid('0C'); // ((A*256)+B)/4
    final speed = await _pid('0D'); // A
    final coolant = await _pid('05'); // A-40
    final throttle = await _pid('11'); // A*100/255
    final volt = await readVoltage();
    return LiveData(
      rpm: rpm != null && rpm.length >= 2 ? (rpm[0] * 256 + rpm[1]) / 4 : null,
      speed: speed != null && speed.isNotEmpty ? speed[0].toDouble() : null,
      coolant: coolant != null && coolant.isNotEmpty ? coolant[0] - 40.0 : null,
      throttle: throttle != null && throttle.isNotEmpty ? throttle[0] * 100 / 255 : null,
      voltage: volt,
    );
  }
}
