import 'package:flutter/material.dart';

import '../features/client/client_screen.dart';

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fussball Client',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
      home: const ClientScreen(),
    );
  }
}
