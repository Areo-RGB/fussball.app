class SplitCheckpoint {
  const SplitCheckpoint({
    required this.deviceId,
    required this.deviceName,
    required this.elapsedMs,
  });

  final String deviceId;
  final String deviceName;
  final int elapsedMs;
}
