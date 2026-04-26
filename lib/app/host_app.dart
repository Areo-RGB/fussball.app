import 'package:flutter/material.dart';

import '../features/host/host_screen.dart';

class HostApp extends StatelessWidget {
  const HostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fussball Host',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey)),
      home: const HostScreen(),
    );
  }
}
