import 'package:flutter_test/flutter_test.dart';

import 'package:fussball_app/shared/utils/time_format.dart';

void main() {
  test('rounds up to centiseconds and formats with two decimals', () {
    expect(formatElapsedMillisRoundUp(0), '0.00s');
    expect(formatElapsedMillisRoundUp(1), '0.01s');
    expect(formatElapsedMillisRoundUp(1620), '1.62s');
    expect(formatElapsedMillisRoundUp(1601), '1.61s');
  });
}
