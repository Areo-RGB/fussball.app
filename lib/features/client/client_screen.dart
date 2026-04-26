import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/device_role.dart';
import '../network/client/client_connection.dart';
import 'client_controller.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  late final ClientController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ClientController();
    _controller.initialize();
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final connected = _controller.connectionState == ClientConnectionState.connected;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    connected ? Icons.check_circle : Icons.sync,
                    size: 80,
                    color: connected ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    connected ? 'Connected to server' : 'Connecting to server...',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(_controller.identityLabel, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('Role: ${_controller.role.label}'),
                  const SizedBox(height: 8),
                  Text('Monitoring: ${_controller.monitoring ? 'ON' : 'OFF'}'),
                  if (_controller.errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _controller.errorText!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
