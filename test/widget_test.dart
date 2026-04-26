import 'package:flutter_test/flutter_test.dart';

import 'package:fussball_app/app/host_app.dart';

void main() {
  testWidgets('host app renders', (WidgetTester tester) async {
    await tester.pumpWidget(const HostApp());
    expect(find.text('Fussball Host'), findsOneWidget);
  });
}
