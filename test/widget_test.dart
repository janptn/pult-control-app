import 'package:flutter_test/flutter_test.dart';
import 'package:pult_control_app/main.dart';

void main() {
  testWidgets('shows the PULT control console', (tester) async {
    await tester.pumpWidget(const PultControlApp());
    expect(find.text('PULT // CONTROL'), findsOneWidget);
  });
}
