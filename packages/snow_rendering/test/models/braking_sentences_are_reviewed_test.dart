// Every spoken sentence that names braking or stopping has been read by a
// person against the rule, and is listed here with the review that cleared it.
//
// WHY THIS TEST EXISTS
// no_braking_prohibition_test.dart holds the rule: a spoken line may ask her
// to avoid abrupt inputs; it must never forbid braking or stopping. Its check
// is lexical, and its own bounds say a new phrasing can evade it, "so a person
// still reads every change to a spoken line". Nothing made that reading
// happen. Probed on 2026-09-25 with 42 prohibitions its authors had not
// written, the widened check caught 5. It let through 「急ブレーキは禁物です。」
// (禁物 is the word JAF's own text uses for "must not"), the polite
// 「〜てはなりません」 of a form its bounds say it knows, any adverb between
// ブレーキ and a negated verb (「ブレーキはできるだけ使わないでください。」),
// 「ブレーキペダルを…」, "Please don't use your brakes." and "You should not
// brake on black ice." No list of phrasings can be complete, and a green
// result from an incomplete list reads as "no line forbids braking" when it
// only means "no line uses a phrasing we thought of". The machine, not a
// reviewer's memory, must make the reading happen, and it must cost less than
// the defect: today four sentences are in scope.
//
// WHAT IT CHECKS
// Every sentence of every spoken line, in both languages, that names braking,
// stopping or the brake pedal must be one of the reviewed sentences below,
// byte for byte. A new or changed sentence fails until a person has read it
// against the rule and added it here with the review that cleared it. The
// lexical check stays: it explains why a known form is wrong, and it still
// runs on every spoken line, reviewed or not.
//
// BOUNDS
// - A prohibition that names neither braking, stopping nor the pedal (for
//   example one about slowing down) is outside this scope.
// - The review is a person's. This test makes it happen; it does not make it
//   right.
// - A NEW top-level announcement constant must be added to _spokenLines() by
//   hand, as in no_braking_prohibition_test.dart.
import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

/// Reviewed sentences, and the review that cleared each one.
const Map<String, String> _reviewed = {
  '制動距離が伸びます。':
      'A fact about stopping distance; asks nothing and forbids nothing.',
  'Stopping distance increases.':
      'A fact about stopping distance; asks nothing and forbids nothing.',
  '速度を落とし、急ブレーキ・急ハンドルは避けてください。':
      'Safety review of the change that replaced 「急ハンドル、急ブレーキは厳禁。」: '
          'a request to avoid abrupt inputs, not a prohibition.',
  'Reduce speed and avoid abrupt braking or steering.':
      'Safety review of the change that replaced "No abrupt steering or '
          'braking.": a request to avoid abrupt inputs, not a prohibition.',
};

final RegExp _jaInScope = RegExp(r'ブレーキ|制動|停止|止ま|停車|ペダル');
final RegExp _enInScope =
    RegExp(r'\bbrak|\bstop|\bpedal', caseSensitive: false);

Map<String, RoadSurfaceAnnouncement> _spokenLines() => {
      for (final s in RoadSurfaceState.values)
        if (s.announcement case final a?) 'RoadSurfaceState.${s.name}': a,
      for (final r in RecommendedResponse.values)
        if (r.announcement case final a?) 'RecommendedResponse.${r.name}': a,
      'invisibleBlackIceAnnouncement': invisibleBlackIceAnnouncement,
      'conditionsUnknownAnnouncement': conditionsUnknownAnnouncement,
      'roadAdvisoryUnmeasuredAnnouncement': roadAdvisoryUnmeasuredAnnouncement,
    };

List<String> _sentences(String text, {required bool ja}) => text
    .split(ja ? RegExp(r'(?<=[。！？])') : RegExp(r'(?<=[.!?;])\s+'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

void main() {
  final lines = _spokenLines();
  final inScope = <String>{};

  test('control: the enumeration reached both black-ice lines', () {
    expect(
      lines.keys,
      containsAll(<String>[
        'invisibleBlackIceAnnouncement',
        'RoadSurfaceState.blackIce',
      ]),
    );
  });

  for (final e in lines.entries) {
    for (final lang in const ['ja', 'en']) {
      test('${e.key} ($lang): every braking or stopping sentence was reviewed',
          () {
        final ja = lang == 'ja';
        final text = ja ? e.value.jaSpokenText : e.value.enSpokenText;
        for (final s in _sentences(text, ja: ja)) {
          if (!(ja ? _jaInScope : _enInScope).hasMatch(s)) continue;
          inScope.add(s);
          expect(_reviewed.containsKey(s), isTrue,
              reason: '${e.key} speaks 「$s」, which names braking or '
                  'stopping and has not been reviewed. A person must read it '
                  'against the rule (a spoken line may ask her to avoid abrupt '
                  'inputs; it must never forbid braking or stopping) and add '
                  'it to _reviewed with the review that cleared it.');
        }
      });
    }
  }

  test('every reviewed sentence is still spoken (no dead entries)', () {
    final spoken = <String>{
      for (final a in lines.values) ...[
        ..._sentences(a.jaSpokenText, ja: true),
        ..._sentences(a.enSpokenText, ja: false),
      ],
    };
    for (final s in _reviewed.keys) {
      expect(spoken, contains(s),
          reason: '「$s」 is listed as reviewed but no spoken line says it. '
              'Remove it: the list must describe what she can hear now.');
    }
  });
}
