import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// ช่องทางส่งข้อมูลไปยังเครื่อง OBD2 (BLE หรือ Wi-Fi)
abstract class ObdTransport {
  Stream<List<int>> get incoming;
  Future<void> connect();
  Future<void> write(List<int> data);
  Future<void> disconnect();
}

/// เครื่อง ELM327 แบบ Wi-Fi: โทรศัพท์ต้องต่อ Wi-Fi ของตัวเครื่องก่อน
/// ค่าเริ่มต้นที่พบบ่อยคือ 192.168.0.10 พอร์ต 35000 (ตรวจสอบกับคู่มือเครื่องของคุณ)
class WifiTransport implements ObdTransport {
  WifiTransport({this.host = '192.168.0.10', this.port = 35000});

  final String host;
  final int port;
  Socket? _socket;
  final StreamController<List<int>> _ctl = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get incoming => _ctl.stream;

  @override
  Future<void> connect() async {
    _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 6));
    _socket!.listen(_ctl.add, onError: (_) {}, onDone: () {});
  }

  @override
  Future<void> write(List<int> data) async {
    final s = _socket;
    if (s == null) throw StateError('ยังไม่ได้เชื่อมต่อ');
    s.add(data);
    await s.flush();
  }

  @override
  Future<void> disconnect() async {
    await _socket?.close();
    _socket = null;
  }
}

/// เครื่อง ELM327 แบบ Bluetooth Low Energy (ใช้ได้ทั้ง Android และ iPhone)
/// เครื่องแต่ละยี่ห้อใช้ UUID ต่างกัน (FFF0, FFE0, 18F0 ฯลฯ)
/// จึงค้นหา characteristic ที่ "รับแจ้งเตือนได้" และ "เขียนได้" จากบริการที่พบแทนการกำหนดตายตัว
class BleTransport implements ObdTransport {
  BleTransport(this.device);

  final BluetoothDevice device;
  BluetoothCharacteristic? _write;
  StreamSubscription<List<int>>? _sub;
  final StreamController<List<int>> _ctl = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get incoming => _ctl.stream;

  @override
  Future<void> connect() async {
    await device.connect(timeout: const Duration(seconds: 15));
    final services = await device.discoverServices();

    BluetoothCharacteristic? notify;
    BluetoothCharacteristic? write;
    for (final s in services) {
      final id = s.uuid.str128.toLowerCase();
      // ข้ามบริการมาตรฐานของ Bluetooth (Generic Access / Generic Attribute)
      if (id.startsWith('00001800') || id.startsWith('00001801')) continue;
      for (final c in s.characteristics) {
        final p = c.properties;
        if (notify == null && (p.notify || p.indicate)) notify = c;
        if (write == null && (p.write || p.writeWithoutResponse)) write = c;
      }
    }
    if (notify == null || write == null) {
      await device.disconnect();
      throw StateError('ไม่พบช่องสื่อสารของเครื่อง OBD2 (อาจไม่ใช่เครื่องแบบ BLE)');
    }

    await notify.setNotifyValue(true);
    _sub = notify.onValueReceived.listen(_ctl.add);
    _write = write;
  }

  @override
  Future<void> write(List<int> data) async {
    final w = _write;
    if (w == null) throw StateError('ยังไม่ได้เชื่อมต่อ');
    await w.write(data, withoutResponse: w.properties.writeWithoutResponse);
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await device.disconnect();
  }
}
