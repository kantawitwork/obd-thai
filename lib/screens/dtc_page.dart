import 'package:flutter/material.dart';

import '../obd/dtc_database.dart';
import '../obd/elm327.dart';

class DtcPage extends StatefulWidget {
  const DtcPage({super.key, required this.client});

  final Elm327 client;

  @override
  State<DtcPage> createState() => _DtcPageState();
}

class _DtcPageState extends State<DtcPage> {
  List<String>? _codes;
  bool _busy = false;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await widget.client.readDtcs();
      if (mounted) setState(() => _codes = codes);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ล้างโค้ดปัญหา?'),
        content: const Text(
          'การล้างโค้ดจะลบข้อมูล Freeze frame และรีเซ็ตสถานะ Readiness ด้วย '
          'ถ้าต้องไปตรวจสภาพหรือวัดไอเสีย ควรขับให้ระบบพร้อมก่อน\n\n'
          'การล้างโค้ดไม่ได้แก้ปัญหา ถ้ารถยังเสียอยู่ไฟเตือนจะกลับมาติดอีก '
          'แนะนำให้จดโค้ดไว้ก่อนล้าง',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ยืนยันล้างโค้ด')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await widget.client.clearDtcs();
      if (!mounted) return;
      if (done) setState(() => _codes = []);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done
            ? 'ล้างโค้ดแล้ว ลองสแกนอีกครั้งเพื่อยืนยัน'
            : 'รถไม่ตอบรับคำสั่งล้างโค้ด ตรวจสอบว่าเปิดกุญแจเป็น ON และดับเครื่องยนต์'),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final codes = _codes;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.search),
          label: Text(codes == null ? 'สแกนโค้ดปัญหา' : 'สแกนอีกครั้ง'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: TextStyle(color: scheme.error, height: 1.5)),
          ),
        const SizedBox(height: 16),
        if (codes == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('กดปุ่มด้านบนเพื่ออ่านโค้ดที่ค้างอยู่ในรถ', textAlign: TextAlign.center),
          )
        else if (codes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.check_circle, size: 40, color: scheme.primary),
                  const SizedBox(height: 8),
                  const Text('ไม่พบโค้ดปัญหา'),
                ],
              ),
            ),
          )
        else ...[
          Text('พบ ${codes.length} โค้ด (แตะเพื่อดูรายละเอียด)'),
          const SizedBox(height: 8),
          for (final c in codes) _DtcTile(code: c),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('ล้างโค้ด'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: scheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _DtcTile extends StatelessWidget {
  const _DtcTile({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final info = DtcDatabase.lookup(code);
    final color = switch (info.level) {
      2 => Colors.redAccent,
      1 => Colors.orangeAccent,
      _ => Colors.lightBlueAccent,
    };
    return Card(
      child: ExpansionTile(
        title: Text(code, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        subtitle: Text(info.title),
        trailing: Text('ความรุนแรง: ${info.levelLabel}', style: TextStyle(color: color, fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('สาเหตุที่พบบ่อย', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(info.causes, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}
