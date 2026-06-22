// Production-seam test: the locale→messages wiring in _buildPretripView.
//
// Every other JA test constructs the card with an explicit PretripMessages.ja /
// BriefingStrings.ja. None goes through the actual production resolution this
// arc introduced — SnowAwarePretripAdvisor(messages:
// PretripMessages.forLanguage(Localizations.localeOf(context).languageCode)).
// So a regression that drops the `messages:` argument — silently reverting HER
// mother's reason chips to English while every other test stays green — would
// not be caught. This test pumps the REAL app under a forced Japanese locale
// and asserts a Japanese reason CHIP (not just card chrome) reaches the screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/main.dart' as main_app;

void main() {
  testWidgets(
      'pre-trip view resolves Japanese reason chips from the ja locale',
      (tester) async {
    // Force the platform locale to Japanese; MaterialApp resolves it against
    // its supportedLocales ([en, ja]) to ja.
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const main_app.SNGNavGettingStarted());
    await tester.pump();

    // Switch to the pre-trip view (the segment label is fixed English chrome).
    await tester.tap(find.text('Pre-trip'));
    await tester.pump();

    // The demo forecast is a whiteout-now / clear-later morning → a waitAdvised
    // verdict whose first reason chip is the visibilityWhiteout chip. Under ja
    // that chip ends in ホワイトアウト状態です — present ONLY if the advisor was given
    // the ja messages table. Drop the `messages:` wiring and this chip reverts
    // to the English "whiteout conditions" and this assertion fails.
    expect(find.textContaining('ホワイトアウト'), findsWidgets,
        reason: 'the JA whiteout reason chip must render under the ja locale');
    expect(find.textContaining('whiteout conditions'), findsNothing,
        reason: 'no English reason chip should leak under the ja locale');
  });
}
