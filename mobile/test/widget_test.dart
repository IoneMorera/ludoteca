import 'package:flutter_test/flutter_test.dart';
import 'package:ludoteca_mobile/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const LudotecaApp());
    expect(find.byType(LudotecaApp), findsOneWidget);
  });
}
