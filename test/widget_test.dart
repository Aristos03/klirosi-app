import 'package:flutter_test/flutter_test.dart';

import 'package:klirosi_app/main.dart';

void main() {
  testWidgets('App starts on the draw tab', (WidgetTester tester) async {
    await tester.pumpWidget(const KlirosiApp());
    await tester.pumpAndSettle();

    expect(find.text('ΚΛΗΡΩΣΗ ΑΥΤΟΚΙΝΗΤΟΥ'), findsOneWidget);
  });
}
