import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klirosi_app/main.dart';

void main() {
  testWidgets('App starts on the draw tab', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KlirosiApp());
    // Avoid pumpAndSettle: the draw screen has a continuously repeating
    // bounce animation, which would never "settle" and time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ΚΛΗΡΩΣΗ ΑΥΤΟΚΙΝΗΤΟΥ'), findsOneWidget);
  });
}
