import 'package:flutter_test/flutter_test.dart';

import 'package:fussball_app/features/motion_detection/motion_math.dart';

void main() {
  test('motion result object stores values', () {
    const result = MotionComputationResult(motionScore: 0.42, currentRoi: <int>[1, 2, 3]);
    expect(result.motionScore, 0.42);
    expect(result.currentRoi, <int>[1, 2, 3]);
  });
}
