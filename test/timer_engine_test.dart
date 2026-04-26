import 'package:flutter_test/flutter_test.dart';

import 'package:fussball_app/features/timer/timer_engine.dart';

void main() {
  test('timer engine state machine start stop reset', () {
    final timer = TimerEngine();

    expect(timer.state, TimerRunState.idle);
    timer.start(1 * 1000000000);
    expect(timer.state, TimerRunState.running);
    expect(timer.elapsedMsAtNs(1600 * 1000000), 600);

    timer.stop(1800 * 1000000);
    expect(timer.state, TimerRunState.stopped);
    expect(timer.elapsedMsAtNs(2500 * 1000000), 800);
    expect(timer.finalElapsedMs, 800);

    timer.reset();
    expect(timer.state, TimerRunState.idle);
    expect(timer.elapsedMsAtNs(9999 * 1000000), 0);
  });
}
