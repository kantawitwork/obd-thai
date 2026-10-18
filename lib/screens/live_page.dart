import 'dart:async';

import 'package:flutter/material.dart';

import '../obd/elm327.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key, required this.client, required this.active});

  final Elm327 client;

  /// อ่านข้อมูลเฉพาะตอนที่แท็บนี้เปิดอยู่
  final bool active;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  Timer? _timer;
  bool _busy = false;
  LiveData? _data;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LivePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.active) {
      _timer ??= Timer.periodic(const Duration(milliseconds: 900), (_) => _poll());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final d = await widget.client.readLive();
      if (mounted) setState(() => _data = d);
    } catch (_) {
      // ข้ามรอบนี้ไป รอบถัดไปจะลองอ่านใหม่
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _fmt(double? v, {int digits = 0}) => v == null ? '--' : v.toStringAsFixed(digits);

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [
        _Tile(label: 'รอบเครื่อง', value: _fmt(d?.rpm), unit: 'rpm', fraction: (d?.rpm ?? 0) / 7000),
        _Tile(label: 'ความเร็ว', value: _fmt(d?.speed), unit: 'km/h', fraction: (d?.speed ?? 0) / 200),
        _Tile(label: 'น้ำหล่อเย็น', value: _fmt(d?.coolant), unit: '°C', fraction: (d?.coolant ?? 0) / 120),
        _Tile(label: 'คันเร่ง', value: _fmt(d?.throttle), unit: '%', fraction: (d?.throttle ?? 0) / 100),
        _Tile(label: 'แบตเตอรี่', value: _fmt(d?.voltage, digits: 1), unit: 'V', fraction: ((d?.voltage ?? 0) / 16)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.unit, required this.fraction});

  final String label;
  final String value;
  final String unit;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text(unit),
              ],
            ),
            LinearProgressIndicator(value: fraction.clamp(0.0, 1.0)),
          ],
        ),
      ),
    );
  }
}
