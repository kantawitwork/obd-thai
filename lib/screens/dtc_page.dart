import 'package:flutter/material.dart';

import '../obd/dtc_database.dart';
import '../obd/elm327.dart';
import '../obd/scan_report.dart';

class DtcPage extends StatefulWidget {
  const DtcPage({super.key, required this.client});

  final Elm327 client;

  @override
  State<DtcPage> createState() => _DtcPageState();
}

class _DtcPageState extends State<DtcPage> {
  ScanReport? _report;
  bool _busy = false;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.client.fullScan();
      if (mounted) setState(() => _report = r);
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
          'และโค้ดถาวรจะไม่ถูกลบ ต้องรอให้ระบบตรวจผ่านเอง\n\n'
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done
            ? 'ล้างโค้ดแล้ว กำลังสแกนซ้ำเพื่อยืนยัน'
            : 'รถไม่ตอบรับคำสั่งล้างโค้ด ตรวจสอบว่าเปิดกุญแจเป็น ON และดับเครื่องยนต์'),
      ));
      if (done) {
        final r = await widget.client.fullScan();
        if (mounted) setState(() => _report = r);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _report;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.search),
          label: Text(r == null ? 'สแกนรถ' : 'สแกนอีกครั้ง'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text('กำลังอ่านข้อมูลจากรถ อาจใช้เวลาสักครู่...'),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_error!, style: TextStyle(color: scheme.error, height: 1.5)),
          ),
        const SizedBox(height: 16),
        if (r == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'กดปุ่มด้านบนเพื่อสแกน แอปจะอ่านโค้ดที่ค้างอยู่ โค้ดที่ยังไม่ยืนยัน '
              'โค้ดถาวร สถานะไฟเตือน และความพร้อมของระบบตรวจสอบ',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.6),
            ),
          )
        else
          ..._buildReport(context, r),
      ],
    );
  }

  List<Widget> _buildReport(BuildContext context, ScanReport r) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final st = r.status;
    final total = r.allCodes.length;
    final canClear = r.stored.codes.isNotEmpty || r.pending.codes.isNotEmpty || (st?.milOn ?? false);

    return [
      // ----- สรุปผล -----
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                total == 0 ? Icons.check_circle : Icons.warning_amber_rounded,
                size: 44,
                color: total == 0 ? scheme.primary : Colors.orangeAccent,
              ),
              const SizedBox(height: 8),
              Text(
                total == 0 ? 'ไม่พบโค้ดปัญหา' : 'พบ $total โค้ด',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text('สแกนเมื่อ ${_time(r.time)}', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // ----- เตือนกรณีข้อมูลขัดกัน -----
      if (st != null && st.milOn && total == 0)
        _note(context, Colors.orangeAccent,
            'ไฟเตือนเครื่องยนต์ยังติดอยู่ แต่ไม่พบโค้ดที่อ่านได้ อาจเป็นโค้ดของระบบอื่น '
            '(เช่น ABS, ถุงลม) ที่แอปนี้ยังอ่านไม่ได้ หรือโค้ดเพิ่งถูกล้าง แนะนำให้ตรวจที่ศูนย์บริการ'),
      if (st != null && st.dtcCount > r.stored.codes.length && r.stored.answered)
        _note(context, Colors.orangeAccent,
            'รถรายงานว่ามีโค้ด ${st.dtcCount} รายการ แต่แอปอ่านได้ ${r.stored.codes.length} รายการ '
            'ลองสแกนอีกครั้ง'),

      // ----- รายการที่ตรวจ -----
      _sectionTitle(context, 'รายการที่ตรวจ'),
      Card(
        child: Column(
          children: [
            _checkRow(context, 'โค้ดที่ค้างอยู่ (Mode 03)', r.stored),
            const Divider(height: 1),
            _checkRow(context, 'โค้ดที่ยังไม่ยืนยัน (Mode 07)', r.pending),
            const Divider(height: 1),
            _checkRow(context, 'โค้ดถาวร (Mode 0A)', r.permanent),
          ],
        ),
      ),
      const SizedBox(height: 4),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'โค้ดที่ยังไม่ยืนยัน คือปัญหาที่ตรวจพบครั้งเดียว ยังไม่ทำให้ไฟเตือนติด '
          'ส่วนโค้ดถาวรจะหายเองเมื่อระบบตรวจผ่านหลังซ่อมแล้ว ล้างด้วยแอปไม่ได้',
          style: TextStyle(fontSize: 12, height: 1.5),
        ),
      ),
      const SizedBox(height: 12),

      // ----- สถานะรถ -----
      _sectionTitle(context, 'สถานะรถ'),
      Card(
        child: Column(
          children: [
            _infoRow(
              'ไฟเตือนเครื่องยนต์ (MIL)',
              st == null ? 'อ่านไม่ได้' : (st.milOn ? 'ติดอยู่' : 'ดับ'),
              color: st == null ? null : (st.milOn ? Colors.orangeAccent : scheme.primary),
            ),
            const Divider(height: 1),
            _infoRow('จำนวนโค้ดที่รถรายงาน', st == null ? '--' : '${st.dtcCount}'),
            const Divider(height: 1),
            _infoRow('ชนิดเครื่องยนต์', st == null ? '--' : (st.isDiesel ? 'ดีเซล' : 'เบนซิน')),
            const Divider(height: 1),
            _infoRow('เลขตัวถัง (VIN)', r.vin ?? 'รถไม่รองรับการอ่าน'),
            const Divider(height: 1),
            _infoRow('โปรโตคอล', widget.client.protocolName.isEmpty ? '--' : widget.client.protocolName),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // ----- Readiness -----
      if (st != null) ...[
        _sectionTitle(context, 'ความพร้อมของระบบตรวจสอบ (${st.readyCount}/${st.supportedCount})'),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < st.monitors.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _monitorRow(context, st.monitors[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '"ยังไม่พร้อม" มักเกิดหลังล้างโค้ดหรือถอดแบตเตอรี่ ต้องขับใช้งานปกติสักพักระบบจึงตรวจครบ '
            'ถ้าจะไปตรวจสภาพรถ ควรให้ขึ้นว่าพร้อมครบก่อน',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
      ],

      // ----- รายละเอียดโค้ด -----
      if (total > 0) ...[
        _sectionTitle(context, 'รายละเอียดโค้ด (แตะเพื่อดู)'),
        for (final c in r.stored.codes) _DtcTile(code: c, kind: 'ค้างอยู่'),
        for (final c in r.pending.codes.where((c) => !r.stored.codes.contains(c)))
          _DtcTile(code: c, kind: 'ยังไม่ยืนยัน'),
        for (final c in r.permanent.codes.where(
            (c) => !r.stored.codes.contains(c) && !r.pending.codes.contains(c)))
          _DtcTile(code: c, kind: 'ถาวร'),
        const SizedBox(height: 8),
      ],

      if (canClear)
        OutlinedButton.icon(
          onPressed: _busy ? null : _clear,
          icon: const Icon(Icons.delete_outline),
          label: const Text('ล้างโค้ด'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: scheme.error,
          ),
        ),
      const SizedBox(height: 24),
    ];
  }

  // ---------------------------------------------------------------- ส่วนประกอบ

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)} น.';
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );

  Widget _note(BuildContext context, Color color, String text) => Card(
        color: color.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(height: 1.5))),
            ],
          ),
        ),
      );

  Widget _infoRow(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ],
        ),
      );

  Widget _checkRow(BuildContext context, String label, DtcResult res) {
    final scheme = Theme.of(context).colorScheme;
    final IconData icon;
    final Color color;
    final String text;
    if (!res.answered) {
      icon = Icons.remove_circle_outline;
      color = Colors.grey;
      text = 'รถไม่รองรับ';
    } else if (res.codes.isEmpty) {
      icon = Icons.check_circle;
      color = scheme.primary;
      text = 'ไม่พบ';
    } else {
      icon = Icons.warning_amber_rounded;
      color = Colors.orangeAccent;
      text = 'พบ ${res.codes.length} โค้ด';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _monitorRow(BuildContext context, Monitor m) {
    final scheme = Theme.of(context).colorScheme;
    final (String text, Color color) = switch (m.state) {
      MonitorState.ready => ('พร้อม', scheme.primary),
      MonitorState.notReady => ('ยังไม่พร้อม', Colors.orangeAccent),
      MonitorState.unsupported => ('รถไม่มีระบบนี้', Colors.grey),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(m.name)),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _DtcTile extends StatelessWidget {
  const _DtcTile({required this.code, required this.kind});

  final String code;
  final String kind;

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
        subtitle: Text('${info.title}\nประเภท: $kind'),
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
