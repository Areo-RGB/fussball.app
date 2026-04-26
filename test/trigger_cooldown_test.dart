import 'package:flutter_test/flutter_test.dart';

import 'package:fussball_app/shared/utils/trigger_cooldown_gate.dart';

void main() {
  test('cooldown gate blocks triggers inside cooldown window', () {
    final gate = TriggerCooldownGate(cooldownMs: 300);

    expect(gate.tryAcquire(1000), isTrue);
    expect(gate.tryAcquire(1100), isFalse);
    expect(gate.tryAcquire(1300), isTrue);
  });
}
