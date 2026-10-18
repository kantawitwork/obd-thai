import 'package:flutter/material.dart';

import 'screens/connect_screen.dart';

void main() {
  runApp(const ObdApp());
}

class ObdApp extends StatelessWidget {
  const ObdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'เช็คโค้ดรถ OBD2',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2FD4A8),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2FD4A8),
        brightness: Brightness.dark,
      ),
      // จำกัดความกว้างให้พอดีเมื่อเปิดบนคอมพิวเตอร์ (หน้าต่างกว้าง)
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: child,
          ),
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}
