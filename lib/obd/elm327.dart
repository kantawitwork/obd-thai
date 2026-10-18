import 'dart:async';

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

  /// แปลงคำตอบ Mode 03 เป็นรหัสโค้ด เช่น P0301
  /// บน CAN คำตอบเป็น 43 <จำนวนโค้ด> <คู่ไบต์ DTC...>
  /// บนโปรโตคอลเก่า คำตอบเป็น 43 <คู่ไบต์ DTC...> เติม 00 00 ให้ครบ
  static List<String> parseDtcs(List<String> lines, {required bool isCan}) {
    final found = <String>[];
    for (final msg in messages(lines)) {
      if (msg.isEmpty || msg[0] != 0x43) continue;
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
