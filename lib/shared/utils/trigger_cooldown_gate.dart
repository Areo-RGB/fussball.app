class TriggerCooldownGate {
  TriggerCooldownGate({required this.cooldownMs});

  final int cooldownMs;
  int _lastTriggerMs = -1;

  bool tryAcquire(int nowMs) {
    if (_lastTriggerMs < 0 || nowMs - _lastTriggerMs >= cooldownMs) {
      _lastTriggerMs = nowMs;
      return true;
    }
    return false;
  }

  void reset() {
    _lastTriggerMs = -1;
  }
}
