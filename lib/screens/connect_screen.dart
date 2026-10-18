import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../obd/elm327.dart';
import '../obd/transport.dart';
import 'main_shell.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  static final RegExp _likely = RegExp(r'veepeak|vpeak|obd|elm|vgate|icar', caseSensitive: false);

  bool _scanning = false;
  bool _connecting = false;
  String? _error;
  List<ScanResult> _results = [];

  String _nameOf(ScanResult r) {
    final adv = r.advertisementData.advName;
    return adv.isNotEmpty ? adv : r.device.platformName;
  }

  Future<bool> _askPermissions() async {
    if (!Platform.isAndroid) return true;
    final r = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final newStyle = r[Permission.bluetoothScan]?.isGranted == true &&
        r[Permission.bluetoothConnect]?.isGranted == true;
    final oldStyle = r[Permission.locationWhenInUse]?.isGranted == true;
    return newStyle || oldStyle;
  }

  Future<void> _scan() async {
    setState(() {
      _error = null;
      _results = [];
      _scanning = true;
    });
    StreamSubscription<List<ScanResult>>? sub;
    try {
      if (!await _askPermissions()) {
        throw 'ต้องอนุญาตสิทธิ์ Bluetooth ก่อนจึงจะค้นหาเครื่องได้';
      }
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        throw 'กรุณาเปิด Bluetooth ของโทรศัพท์ก่อน';
      }
      sub = FlutterBluePlus.scanResults.listen((list) {
        final named = list.where((r) => _nameOf(r).isNotEmpty).toList()
          ..sort((a, b) {
            final la = _likely.hasMatch(_nameOf(a)) ? 0 : 1;
            final lb = _likely.hasMatch(_nameOf(b)) ? 0 : 1;
            return la != lb ? la - lb : b.rssi.compareTo(a.rssi);
          });
        if (mounted) setState(() => _results = named);
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((v) => v == false).first;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      await sub?.cancel();
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(ObdTransport transport) async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final client = Elm327(transport);
    try {
      await client.open();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainShell(client: client)),
      );
    } catch (e) {
      await client.close();
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'เชื่อมต่อไม่สำเร็จ: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('เชื่อมต่อเครื่อง OBD2')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '1. เสียบเครื่อง OBD2 ที่ช่องใต้คอพวงมาลัย\n'
                    '2. เปิดกุญแจเป็น ON (ไม่ต้องสตาร์ตเครื่อง)\n'
                    '3. เลือกวิธีเชื่อมต่อด้านล่าง',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_scanning || _connecting) ? null : _scan,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(_scanning ? 'กำลังค้นหา...' : 'ค้นหาเครื่อง Bluetooth'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              if (_scanning) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              const SizedBox(height: 8),
              for (final r in _results)
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.bluetooth,
                      color: _likely.hasMatch(_nameOf(r)) ? scheme.primary : null,
                    ),
                    title: Text(_nameOf(r)),
                    subtitle: Text(_likely.hasMatch(_nameOf(r)) ? 'น่าจะเป็นเครื่อง OBD2' : 'อุปกรณ์อื่น'),
                    trailing: const Text('เชื่อมต่อ'),
                    onTap: _connecting ? null : () => _connect(BleTransport(r.device)),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: (_scanning || _connecting) ? null : () => _connect(WifiTransport()),
                icon: const Icon(Icons.wifi),
                label: const Text('เชื่อมต่อผ่าน Wi-Fi (เครื่องแบบ Wi-Fi)'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: scheme.error, height: 1.5)),
                ),
              const SizedBox(height: 16),
              const ExpansionTile(
                title: Text('ไม่พบเครื่องหรือเชื่อมต่อไม่ได้?'),
                childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• เครื่องแบบ Bluetooth Classic (ไม่ใช่ BLE) จะไม่ปรากฏในรายการนี้ และใช้กับ iPhone ไม่ได้ '
                    'ถ้าใช้ iPhone ให้ใช้เครื่องแบบ BLE หรือ Wi-Fi\n'
                    '• เครื่องแบบ Wi-Fi: ไปที่ตั้งค่า Wi-Fi ของโทรศัพท์แล้วต่อกับชื่อ Wi-Fi ของตัวเครื่องก่อน '
                    'จากนั้นกลับมากดปุ่ม Wi-Fi ในแอป (ถ้าโทรศัพท์ถามว่าจะคงการเชื่อมต่อที่ไม่มีอินเทอร์เน็ตไหม ให้เลือกคงไว้)\n'
                    '• ตรวจสอบว่ากุญแจอยู่ที่ ON และไม่มีแอปอื่นเชื่อมต่อกับเครื่องอยู่\n'
                    '• ลองถอดเครื่องออก 10 วินาทีแล้วเสียบใหม่',
                    style: TextStyle(height: 1.6),
                  ),
                ],
              ),
            ],
          ),
          if (_connecting)
            Container(
              color: Colors.black.withOpacity(0.7),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('กำลังเชื่อมต่อกับรถ...\nอาจใช้เวลาสักครู่', textAlign: TextAlign.center),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
