import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../maintenance/maintenance_models.dart';
import '../maintenance/maintenance_store.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({
    super.key,
    required this.store,
    required this.vehicleKey,
    required this.vehicleLabel,
    required this.hasVin,
  });

  final MaintenanceStore store;
  final String vehicleKey;
  final String vehicleLabel;
  final bool hasVin;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final TextEditingController _km = TextEditingController();
  String? _kmLoadedFor;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  MaintenanceStore get store => widget.store;
  String get key => widget.vehicleKey;

  Color _color(DueLevel l, ColorScheme s) => switch (l) {
        DueLevel.ok => s.primary,
        DueLevel.soon => Colors.orangeAccent,
        DueLevel.overdue => Colors.redAccent,
        DueLevel.none => Colors.grey,
      };

  Future<void> _saveKm() async {
    final v = int.tryParse(_km.text.trim());
    if (v == null || v <= 0) {
      _toast('กรอกเลขไมล์เป็นตัวเลข เช่น 45000');
      return;
    }
    await store.setCurrentKm(key, v);
    FocusManager.instance.primaryFocus?.unfocus();
    _toast('บันทึกเลขไมล์แล้ว');
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _add({String? typeId}) async {
    final rec = await showDialog<MaintenanceRecord>(
      context: context,
      builder: (_) => _AddRecordDialog(
        vehicleKey: key,
        initialTypeId: typeId ?? 'engine_oil',
        defaultKm: store.currentKmFor(key),
      ),
    );
    if (rec != null) {
      await store.addRecord(rec);
      if (mounted) _toast('บันทึกแล้ว');
    }
  }

  Future<void> _editInterval(ServiceType t) async {
    final iv = store.intervalFor(key, t);
    final kmC = TextEditingController(text: '${iv[0]}');
    final moC = TextEditingController(text: '${iv[1]}');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('รอบ: ${t.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ใส่ 0 ถ้าไม่ต้องการให้นับด้านนั้น ปรับให้ตรงกับคู่มือรถของคุณ',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: kmC,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'ทุกกี่กิโลเมตร', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: moC,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'ทุกกี่เดือน', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          if (store.hasCustomInterval(key, t))
            TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('คืนค่าเริ่มต้น')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('บันทึก')),
        ],
      ),
    );
    final km = int.tryParse(kmC.text.trim()) ?? 0;
    final mo = int.tryParse(moC.text.trim()) ?? 0;
    // รอให้แอนิเมชันปิดหน้าต่างจบก่อนจึงปล่อยตัวควบคุมข้อความ
    Future.delayed(const Duration(milliseconds: 500), () {
      kmC.dispose();
      moC.dispose();
    });
    if (action == 'save') {
      await store.setInterval(key, t, km, mo);
    } else if (action == 'reset') {
      await store.resetInterval(key, t);
    }
  }

  Future<void> _delete(MaintenanceRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบบันทึกนี้?'),
        content: Text('${serviceTypeOf(r.typeId).name}\n${fmtDate(r.date)} · ${fmtNum(r.km)} กม.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok == true) await store.deleteRecord(r.id);
  }

  Future<void> _copy() async {
    final recs = store.recordsFor(key);
    if (recs.isEmpty) {
      _toast('ยังไม่มีบันทึกให้คัดลอก');
      return;
    }
    final b = StringBuffer('ประวัติบำรุงรักษา – ${widget.vehicleLabel}\n');
    for (final r in recs) {
      b.write('${fmtDate(r.date)} | ${fmtNum(r.km)} กม. | ${serviceTypeOf(r.typeId).name}');
      if (r.cost != null) b.write(' | ${fmtNum(r.cost!)} บาท');
      if (r.note.isNotEmpty) b.write(' | ${r.note}');
      b.write('\n');
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    _toast('คัดลอกแล้ว นำไปวางในแชตหรืออีเมลได้');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.loaded) return const Center(child: CircularProgressIndicator());
        if (_kmLoadedFor != key) {
          _kmLoadedFor = key;
          _km.text = store.currentKmFor(key)?.toString() ?? '';
        }
        final scheme = Theme.of(context).colorScheme;
        final recs = store.recordsFor(key);
        final scheduled = kServiceTypes.where((t) => t.scheduled || store.hasCustomInterval(key, t)).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (store.saveFailed)
              Card(
                color: Colors.redAccent.withValues(alpha: 0.15),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('บันทึกลงเครื่องไม่สำเร็จ ข้อมูลล่าสุดอาจหายเมื่อปิดแอป',
                      style: TextStyle(height: 1.5)),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.vehicleLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      widget.hasVin
                          ? 'บันทึกผูกกับเลขตัวถังของรถคันนี้ เก็บในโทรศัพท์/คอมพิวเตอร์เครื่องนี้เท่านั้น'
                          : 'รถคันนี้ไม่ตอบเลขตัวถัง บันทึกจะรวมเป็น "รถของฉัน" ถ้าใช้กับรถหลายคัน บันทึกจะปนกัน',
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('เลขไมล์ปัจจุบัน (อ่านจากหน้าปัดรถ)', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _km,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(suffixText: 'กม.', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _saveKm,
                          style: FilledButton.styleFrom(minimumSize: const Size(80, 56)),
                          child: const Text('บันทึก'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'แอปอ่านเลขไมล์จากรถไม่ได้ ต้องกรอกเอง ยิ่งอัปเดตบ่อย การแจ้งสถานะยิ่งแม่น',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _add(),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มบันทึกใหม่'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 20),
            Text('สถานะการบำรุงรักษา',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              'รอบเริ่มต้นเป็นค่าโดยประมาณทั่วไป ไม่ใช่ข้อกำหนดของรถคุณ แตะ ⚙ เพื่อปรับตามคู่มือรถ',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 8),
            for (final t in scheduled)
              Builder(builder: (context) {
                final due = store.dueFor(key, t);
                final iv = store.intervalFor(key, t);
                final cycle = [
                  if (iv[0] > 0) 'ทุก ${fmtNum(iv[0])} กม.',
                  if (iv[1] > 0) 'ทุก ${iv[1]} เดือน',
                ].join(' หรือ ');
                return Card(
                  child: ListTile(
                    onTap: () => _add(typeId: t.id),
                    title: Text(t.name),
                    subtitle: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: due.text,
                          style: TextStyle(color: _color(due.level, scheme), fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: cycle.isEmpty ? '' : '\n$cycle'),
                      ]),
                    ),
                    isThreeLine: cycle.isNotEmpty,
                    trailing: IconButton(
                      tooltip: 'ตั้งรอบ',
                      icon: const Icon(Icons.tune),
                      onPressed: () => _editInterval(t),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 20),
            Text('ประวัติ (${recs.length})',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (recs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('ยังไม่มีบันทึก กด "เพิ่มบันทึกใหม่" ได้เลย', textAlign: TextAlign.center),
              ),
            for (final r in recs)
              Card(
                child: ListTile(
                  title: Text(serviceTypeOf(r.typeId).name),
                  subtitle: Text(
                    '${fmtDate(r.date)} · ${fmtNum(r.km)} กม.'
                    '${r.cost == null ? '' : ' · ${fmtNum(r.cost!)} บาท'}'
                    '${r.note.isEmpty ? '' : '\n${r.note}'}',
                  ),
                  isThreeLine: r.note.isNotEmpty,
                  trailing: IconButton(
                    tooltip: 'ลบ',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(r),
                  ),
                ),
              ),
            if (recs.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _copy,
                icon: const Icon(Icons.copy),
                label: const Text('คัดลอกประวัติไปแชร์'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _AddRecordDialog extends StatefulWidget {
  const _AddRecordDialog({
    required this.vehicleKey,
    required this.initialTypeId,
    required this.defaultKm,
  });

  final String vehicleKey;
  final String initialTypeId;
  final int? defaultKm;

  @override
  State<_AddRecordDialog> createState() => _AddRecordDialogState();
}

class _AddRecordDialogState extends State<_AddRecordDialog> {
  late String _typeId = widget.initialTypeId;
  DateTime _date = DateTime.now();
  late final TextEditingController _km = TextEditingController(text: widget.defaultKm?.toString() ?? '');
  final TextEditingController _cost = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _km.dispose();
    _cost.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 15),
      lastDate: now,
    );
    if (d != null) setState(() => _date = d);
  }

  void _submit() {
    final km = int.tryParse(_km.text.trim());
    if (km == null || km <= 0) {
      setState(() => _error = 'กรอกเลขไมล์ตอนที่ทำรายการนี้ (ตัวเลข เช่น 45000)');
      return;
    }
    final cost = int.tryParse(_cost.text.trim());
    Navigator.pop(
      context,
      MaintenanceRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        vehicleKey: widget.vehicleKey,
        typeId: _typeId,
        date: _date,
        km: km,
        cost: cost,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เพิ่มบันทึกบำรุงรักษา'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _typeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'รายการ', border: OutlineInputBorder()),
              items: [
                for (final t in kServiceTypes) DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: (v) => setState(() => _typeId = v ?? _typeId),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('วันที่ทำ: ${fmtDate(_date)}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _km,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'เลขไมล์ตอนทำ',
                suffixText: 'กม.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'ค่าใช้จ่าย (ไม่บังคับ)',
                suffixText: 'บาท',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ เช่น ชื่ออู่ ยี่ห้อน้ำมัน (ไม่บังคับ)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        FilledButton(onPressed: _submit, child: const Text('บันทึก')),
      ],
    );
  }
}
