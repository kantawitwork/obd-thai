import 'package:flutter/material.dart';

import '../obd/elm327.dart';
import '../obd/scan_report.dart';
import 'connect_screen.dart';
import 'dtc_page.dart';
import '../maintenance/maintenance_store.dart';
import 'live_page.dart';
import 'maintenance_page.dart';
import 'vehicle_info_card.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.client});

  final Elm327 client;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  double? _voltage;
  VehicleStatus? _status;

  final MaintenanceStore _store = MaintenanceStore();
  String _vehicleKey = 'my-car';
  String _vehicleLabel = 'รถของฉัน (อ่านเลขตัวถังไม่ได้)';
  bool _hasVin = false;

  @override
  void initState() {
    super.initState();
    _store.load();
    _loadInfo();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    try {
      final v = await widget.client.readVoltage();
      if (mounted) setState(() => _voltage = v);
    } catch (_) {}
    try {
      final s = await widget.client.readStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {}
    try {
      final vin = await widget.client.readVin();
      if (vin != null && mounted) {
        setState(() {
          _vehicleKey = vin;
          _vehicleLabel = 'เลขตัวถัง $vin';
          _hasVin = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _disconnect() async {
    await widget.client.close();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['ภาพรวมรถ', 'โค้ดปัญหา', 'ข้อมูลสด', 'บำรุงรักษา'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          IconButton(
            tooltip: 'ตัดการเชื่อมต่อ',
            icon: const Icon(Icons.link_off),
            onPressed: _disconnect,
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _Overview(
            client: widget.client,
            voltage: _voltage,
            status: _status,
            onRefresh: _loadInfo,
            onGo: (i) => setState(() => _index = i),
          ),
          DtcPage(client: widget.client),
          LivePage(client: widget.client, active: _index == 2),
          MaintenancePage(
            store: _store,
            vehicleKey: _vehicleKey,
            vehicleLabel: _vehicleLabel,
            hasVin: _hasVin,
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final due = _store.loaded ? _store.dueCount(_vehicleKey) : 0;
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'ภาพรวม'),
              const NavigationDestination(
                  icon: Icon(Icons.warning_amber_outlined),
                  selectedIcon: Icon(Icons.warning_amber),
                  label: 'โค้ดปัญหา'),
              const NavigationDestination(
                  icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'ข้อมูลสด'),
              NavigationDestination(
                icon: Badge(
                  label: Text('$due'),
                  isLabelVisible: due > 0,
                  child: const Icon(Icons.build_outlined),
                ),
                selectedIcon: Badge(
                  label: Text('$due'),
                  isLabelVisible: due > 0,
                  child: const Icon(Icons.build),
                ),
                label: 'บำรุงรักษา',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.client,
    required this.voltage,
    required this.status,
    required this.onRefresh,
    required this.onGo,
  });

  final Elm327 client;
  final double? voltage;
  final VehicleStatus? status;
  final VoidCallback onRefresh;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: scheme.primary),
                    const SizedBox(width: 8),
                    Text('เชื่อมต่อแล้ว', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'โปรโตคอล: ${client.protocolName.isEmpty ? 'ไม่ทราบ' : client.protocolName}\n'
                  'แรงดันแบตเตอรี่: ${voltage == null ? '--' : '${voltage!.toStringAsFixed(1)} V'}',
                  style: const TextStyle(height: 1.6),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'ไฟเตือนเครื่องยนต์',
                value: status == null ? '--' : (status!.milOn ? 'ติดอยู่' : 'ดับ'),
                color: status == null ? null : (status!.milOn ? Colors.orangeAccent : scheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'ระบบตรวจสอบพร้อม',
                value: status == null ? '--' : '${status!.readyCount}/${status!.supportedCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('รีเฟรชสถานะ'),
          ),
        ),
        const SizedBox(height: 4),
        VehicleInfoCard(client: client),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => onGo(1),
          icon: const Icon(Icons.search),
          label: const Text('สแกนโค้ดปัญหา'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => onGo(2),
          icon: const Icon(Icons.speed),
          label: const Text('ดูข้อมูลสด'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
