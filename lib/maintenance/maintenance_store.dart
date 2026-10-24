import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'maintenance_models.dart';

/// เก็บบันทึกบำรุงรักษาในเครื่องของผู้ใช้เท่านั้น (ไม่ส่งออกอินเทอร์เน็ต)
class MaintenanceStore extends ChangeNotifier {
  static const _key = 'maintenance_v1';

  final List<MaintenanceRecord> _records = [];
  final Map<String, int> _currentKm = {};
  final Map<String, List<int>> _intervals = {};

  bool loaded = false;
  bool _disposed = false;

  /// true เมื่อบันทึกลงเครื่องไม่สำเร็จ (ข้อมูลอาจหายเมื่อปิดแอป)
  bool saveFailed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    // กันเรียกหลังปิดหน้าจอ (เช่น ตัดการเชื่อมต่อระหว่างกำลังบันทึก)
    if (!_disposed) super.notifyListeners();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw);
        if (j is Map) {
          final recs = j['records'];
          if (recs is List) {
            for (final r in recs) {
              final rec = MaintenanceRecord.fromJson(r);
              if (rec != null) _records.add(rec);
            }
          }
          final km = j['currentKm'];
          if (km is Map) {
            km.forEach((k, v) {
              if (v is int) _currentKm['$k'] = v;
            });
          }
          final iv = j['intervals'];
          if (iv is Map) {
            iv.forEach((k, v) {
              if (v is List && v.length == 2 && v[0] is int && v[1] is int) {
                _intervals['$k'] = [v[0] as int, v[1] as int];
              }
            });
          }
        }
      }
    } catch (_) {
      // ข้อมูลเสียหายหรืออ่านไม่ได้ เริ่มจากว่าง
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ok = await p.setString(
        _key,
        jsonEncode({
          'records': _records.map((r) => r.toJson()).toList(),
          'currentKm': _currentKm,
          'intervals': _intervals,
        }),
      );
      saveFailed = !ok;
    } catch (_) {
      saveFailed = true;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ ข้อมูล

  List<MaintenanceRecord> recordsFor(String vehicleKey) {
    final list = _records.where((r) => r.vehicleKey == vehicleKey).toList();
    list.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.km.compareTo(a.km);
    });
    return list;
  }

  int? currentKmFor(String vehicleKey) => _currentKm[vehicleKey];

  /// รอบที่ใช้จริง (ค่าที่ผู้ใช้ตั้ง หรือค่าเริ่มต้น) เป็น [กม., เดือน]
  List<int> intervalFor(String vehicleKey, ServiceType t) =>
      _intervals['$vehicleKey|${t.id}'] ?? [t.km, t.months];

  bool hasCustomInterval(String vehicleKey, ServiceType t) => _intervals.containsKey('$vehicleKey|${t.id}');

  MaintenanceRecord? lastOf(String vehicleKey, String typeId) {
    final list = recordsFor(vehicleKey).where((r) => r.typeId == typeId);
    return list.isEmpty ? null : list.first;
  }

  DueStatus dueFor(String vehicleKey, ServiceType t, {DateTime? today}) {
    final iv = intervalFor(vehicleKey, t);
    return computeDue(
      km: iv[0],
      months: iv[1],
      last: lastOf(vehicleKey, t.id),
      currentKm: currentKmFor(vehicleKey),
      today: today ?? DateTime.now(),
    );
  }

  /// จำนวนรายการที่ใกล้ถึงกำหนดหรือเกินกำหนด
  int dueCount(String vehicleKey) {
    var n = 0;
    for (final t in kServiceTypes) {
      final s = dueFor(vehicleKey, t).level;
      if (s == DueLevel.soon || s == DueLevel.overdue) n++;
    }
    return n;
  }

  // ------------------------------------------------------------------ แก้ไข

  Future<void> addRecord(MaintenanceRecord r) async {
    _records.add(r);
    // ถ้าเลขไมล์ที่จดมากกว่าเลขไมล์ปัจจุบันที่เคยกรอก ให้ปรับตาม
    final cur = _currentKm[r.vehicleKey];
    if (cur == null || r.km > cur) _currentKm[r.vehicleKey] = r.km;
    await _save();
  }

  Future<void> deleteRecord(String id) async {
    _records.removeWhere((r) => r.id == id);
    await _save();
  }

  Future<void> setCurrentKm(String vehicleKey, int km) async {
    _currentKm[vehicleKey] = km;
    await _save();
  }

  Future<void> setInterval(String vehicleKey, ServiceType t, int km, int months) async {
    _intervals['$vehicleKey|${t.id}'] = [km, months];
    await _save();
  }

  Future<void> resetInterval(String vehicleKey, ServiceType t) async {
    _intervals.remove('$vehicleKey|${t.id}');
    await _save();
  }
}
