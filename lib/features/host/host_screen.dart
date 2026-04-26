import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/device_role.dart';
import '../../shared/utils/time_format.dart';
import 'host_controller.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  late final HostController _controller;

  @override
  void initState() {
    super.initState();
    _controller = HostController();
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fussball Host'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Lobby'),
              Tab(text: 'Timer'),
            ],
          ),
        ),
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return TabBarView(
              children: [
                _LobbyTab(controller: _controller),
                _TimerTab(controller: _controller),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LobbyTab extends StatelessWidget {
  const _LobbyTab({required this.controller});

  final HostController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: controller.monitoringArmed
                      ? controller.stopMonitoring
                      : controller.startMonitoring,
                  icon: Icon(controller.monitoringArmed ? Icons.stop : Icons.play_arrow),
                  label: Text(controller.monitoringArmed ? 'Stop Monitoring' : 'Start Monitoring'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: devices.isEmpty
              ? const Center(child: Text('No connected client devices yet.'))
              : ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.displayName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text('Device: ${device.device}'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Role:'),
                                const SizedBox(width: 8),
                                DropdownButton<DeviceRole>(
                                  value: device.role,
                                  items: DeviceRole.values
                                      .map(
                                        (role) => DropdownMenuItem<DeviceRole>(
                                          value: role,
                                          child: Text(role.label),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (role) {
                                    if (role != null) {
                                      controller.setRole(device.deviceId, role);
                                    }
                                  },
                                ),
                                const Spacer(),
                                Icon(
                                  device.synced ? Icons.check_circle : Icons.sync_problem,
                                  color: device.synced ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Text('Sync: ${device.latencyMs?.toString() ?? '--'} ms'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('FPS: ${device.currentFps?.toStringAsFixed(1) ?? '--'}'),
                            const SizedBox(height: 8),
                            Text('Sensitivity: ${(device.sensitivity * 100).round()}%'),
                            Slider(
                              value: device.sensitivity,
                              min: 0,
                              max: 1,
                              onChanged: (value) =>
                                  controller.setSensitivity(device.deviceId, value),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                onPressed: () => controller.testLatency(device.deviceId),
                                child: const Text('Test Latency'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TimerTab extends StatelessWidget {
  const _TimerTab({required this.controller});

  final HostController controller;

  @override
  Widget build(BuildContext context) {
    final splits = controller.timerEngine.splits;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Center(
              child: Text(
                controller.timerDisplay,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 120,
                  height: 1,
                ),
              ),
            ),
          ),
          Center(
            child: FilledButton.icon(
              onPressed: controller.resetTimer,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                textStyle: Theme.of(context).textTheme.headlineSmall,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Reset'),
            ),
          ),
          const SizedBox(height: 28),
          Text('Splits', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Expanded(
            flex: 2,
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: splits.isEmpty
                  ? const Center(child: Text('No split checkpoints yet.'))
                  : ListView.separated(
                      itemCount: splits.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final split = splits[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          leading: Text(
                            '#${index + 1}',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          title: Text(split.deviceName),
                          trailing: Text(
                            formatElapsedMillisRoundUp(split.elapsedMs),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
