import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../obd/elm327.dart';
import '../obd/scan_report.dart';
import '../obd/vin_decoder.dart';

/// การ์ดอ่านข้อมูลรถและกล่อง ECU (เลขตัวถัง, รหัสซอฟต์แวร์, ระยะทางตั้งแต่ล้างโค้ด ฯลฯ)
class VehicleInfoCard extends StatefulWidget {
  const VehicleInfoCard({super.key, required this.client});

  final Elm327 client;

  @override
  State<VehicleInfoCard> createState() => _VehicleInfoCardState();
}

class _VehicleInfoCardState extends State<VehicleInfoCard> {
  VehicleInfo? _info;
  bool _busy = false;
  String? _error;

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final i = await widget.client.readVehicleInfo();
      if (mounted) setState(() => _info = i);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = _info;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ข้อมูลรถและกล่อง ECU',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _read,
              icon: const Icon(Icons.memory),
              label: Text(info == null ? 'อ่านข้อมูลรถและ ECU' : 'อ่านอีกครั้ง'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 8),
                    Text('กำลังอ่านข้อมูลจากกล่อง ECU อาจใช้เวลาประมาณครึ่งนาที...'),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: scheme.error, height: 1.5)),
              ),
            if (info != null) ...[
              const SizedBox(height: 12),
              if (info.isEmpty)
                const Text(
                  'รถคันนี้ไม่ตอบข้อมูลเหล่านี้ ซึ่งพบได้บ่อยในรถรุ่นเก่าหรือบางยี่ห้อ ไม่ได้แปลว่าแอปเสีย',
                  style: TextStyle(height: 1.5),
                )
              else
                ..._rows(context, info),
            ],
            const SizedBox(height: 8),
            const ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('ทำไมไม่มีเลขเครื่องยนต์และเลขไมล์?'),
              childrenPadding: EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• เลขเครื่องยนต์ คือเลขที่ปั๊มบนเสื้อสูบ ไม่ได้ถูกเก็บในกล่อง ECU และไม่มีคำสั่งมาตรฐานให้อ่าน '
                  'ต้องดูที่ตัวเครื่องหรือเล่มทะเบียน ส่วน "ซีเรียลของกล่อง ECU" ที่แอปแสดงเป็นเลขของกล่องควบคุมเอง ไม่ใช่เลขเครื่อง\n'
                  '• เลขไมล์จริง เก็บอยู่ที่ชุดหน้าปัด และแต่ละยี่ห้ออ่านด้วยวิธีเฉพาะที่ผู้ผลิตไม่เปิดเผย '
                  'ค่า "ระยะทางตั้งแต่ล้างโค้ด" ที่แสดงจึงไม่ใช่เลขไมล์ แต่บอกได้ว่าล้างโค้ดมาแล้วขับไปไกลแค่ไหน '
                  'ถ้าตัวเลขน้อยผิดปกติ แปลว่าเพิ่งล้างโค้ดหรือถอดแบตเตอรี่\n'
                  '• ประวัติซ่อมบำรุง ไม่ได้ถูกบันทึกไว้ในรถ',
                  style: TextStyle(height: 1.6, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context, VehicleInfo i) {
    final rows = <Widget>[];

    void add(String label, String? value, {bool copyable = false}) {
      if (value == null || value.isEmpty) return;
      if (rows.isNotEmpty) rows.add(const Divider(height: 1));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label)),
            Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (copyable)
              IconButton(
                tooltip: 'คัดลอก',
                icon: const Icon(Icons.copy, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คัดลอกแล้ว')));
                },
              ),
          ],
        ),
      ));
    }

    add('เลขตัวถัง (VIN)', i.vin, copyable: true);
    if (i.vin != null) {
      final d = VinDecoder.decode(i.vin!);
      add('ประเทศผู้ผลิต', d.country);
      add('ผู้ผลิต (คาดว่า)', d.maker);
      add('ปีรุ่น (โดยประมาณ)', d.modelYear == null ? null : '${d.modelYear} (ผู้ผลิตบางรายไม่ใช้หลักนี้)');
    }
    add('ชื่อ ECU', i.ecuNames.join('\n'));
    add('รหัสซอฟต์แวร์', i.calibrationIds.join('\n'), copyable: i.calibrationIds.isNotEmpty);
    add('เวอร์ชันซอฟต์แวร์', i.softwareVersion);
    add('เลขชิ้นส่วน ECU', i.partNumber, copyable: i.partNumber != null);
    add('ซีเรียลกล่อง ECU', i.ecuSerial, copyable: i.ecuSerial != null);
    add('ขับตั้งแต่ล้างโค้ด', i.kmSinceCleared == null ? null : '${i.kmSinceCleared} กม.');
    add('ขับขณะไฟเตือนติด', i.kmWithMil == null ? null : '${i.kmWithMil} กม.');
    add('เครื่องทำงานตั้งแต่ล้างโค้ด',
        i.minutesSinceCleared == null ? null : '${(i.minutesSinceCleared! / 60).toStringAsFixed(1)} ชม.');

    final warn = i.vin == null ? const <String>[] : VinDecoder.decode(i.vin!).warnings;
    return [
      ...rows,
      for (final w in warn)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(w, style: const TextStyle(color: Colors.orangeAccent, height: 1.5)),
        ),
    ];
  }
}
