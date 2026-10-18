import 'package:flutter/material.dart';

import '../obd/elm327.dart';
import 'connect_screen.dart';
import 'dtc_page.dart';
import 'live_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.client});

  final Elm327 client;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  double? _voltage;

  @override
  void initState() {
    super.initState();
    _loadVoltage();
  }

  Future<void> _loadVoltage() async {
    try {
      final v = await widget.client.readVoltage();
      if (mounted) setState(() => _voltage = v);
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
    const titles = ['ภาพรวมรถ', 'โค้ดปัญหา', 'ข้อมูลสด'];
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
            onGo: (i) => setState(() => _index = i),
          ),
          DtcPage(client: widget.client),
          LivePage(client: widget.client, active: _index == 2),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'ภาพรวม'),
          NavigationDestination(
              icon: Icon(Icons.warning_amber_outlined),
              selectedIcon: Icon(Icons.warning_amber),
              label: 'โค้ดปัญหา'),
          NavigationDestination(
              icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'ข้อมูลสด'),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.client, required this.voltage, required this.onGo});

  final Elm327 client;
  final double? voltage;
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
