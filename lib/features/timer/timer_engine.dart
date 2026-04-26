import '../../shared/models/split_checkpoint.dart';

enum TimerRunState { idle, running, stopped }

class TimerEngine {
  TimerRunState state = TimerRunState.idle;
  int? startAtNs;
  int? stopAtNs;
  final List<SplitCheckpoint> splits = <SplitCheckpoint>[];

  void reset() {
    state = TimerRunState.idle;
    startAtNs = null;
    stopAtNs = null;
    splits.clear();
  }

  void start(int atNs) {
    if (state == TimerRunState.running) {
      return;
    }
    state = TimerRunState.running;
    startAtNs = atNs;
    stopAtNs = null;
    splits.clear();
  }

  void stop(int atNs) {
    if (state != TimerRunState.running) {
      return;
    }
    state = TimerRunState.stopped;
    stopAtNs = atNs;
  }

  void addSplit({required String deviceId, required String deviceName, required int atNs}) {
    final start = startAtNs;
    if (state != TimerRunState.running || start == null) {
      return;
    }

    splits.add(
      SplitCheckpoint(
        deviceId: deviceId,
        deviceName: deviceName,
        elapsedMs: _nsToMsCeil(atNs - start),
      ),
    );
  }

  int elapsedNsAt(int nowNs) {
    final start = startAtNs;
    if (start == null) {
      return 0;
    }
    if (state == TimerRunState.stopped && stopAtNs != null) {
      return stopAtNs! - start;
    }
    return nowNs - start;
  }

  int elapsedMsAtNs(int nowNs) => _nsToMsCeil(elapsedNsAt(nowNs));

  int get finalElapsedMs {
    if (state != TimerRunState.stopped || startAtNs == null || stopAtNs == null) {
      return 0;
    }
    return _nsToMsCeil(stopAtNs! - startAtNs!);
  }

  int _nsToMsCeil(int nanoseconds) {
    if (nanoseconds <= 0) {
      return 0;
    }
    return (nanoseconds / Duration.microsecondsPerMillisecond / 1000).ceil();
  }
}
