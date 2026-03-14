import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_example/main.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('renders SNGNav example shell', (tester) async {
    await tester.pumpWidget(
      const SngNavExampleApp(
        homeOverride: Scaffold(
          body: Column(
            children: [
              Text('SNGNav Example'),
              Text('What This Shows'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SNGNav Example'), findsOneWidget);
    expect(find.text('What This Shows'), findsOneWidget);
  });
}