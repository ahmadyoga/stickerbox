import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_creator/widgets/toast.dart';

void main() {
  testWidgets('showToast displays the message in a SnackBar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showToast(context, 'Sticker added'),
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pump();

    expect(find.text('Sticker added'), findsOneWidget);
  });
}
