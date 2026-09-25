// No spoken line in this package may forbid braking or stopping.
//
// WHY THIS TEST EXISTS
// Before 0.3.4, both black-ice lines said 「急ハンドル、急ブレーキは厳禁。」 and
// "No abrupt steering or braking." 急ブレーキ is also the everyday word for an
// emergency stop, and 厳禁 admits no exception, so the sentence, read
// literally, forbids the one act a driver may need on ice. It is spoken at a
// moment a data refresh chose, not one her traffic chose. A driver who has
// just heard that stopping is forbidden may hesitate at the moment she needs
// to stop. A spoken line may ASK her to avoid abrupt inputs; it must never
// FORBID braking or stopping.
//
// WHAT IT CHECKS
// Every spoken line this package exports, in both languages, sentence by
// sentence: a sentence that names braking or stopping must not carry an
// absolute prohibition, and no sentence may negate a braking verb.
//
// BOUNDS
// - Lexical. It catches the known class of wording; a new phrasing can evade
//   it, so a person still reads every change to a spoken line.
// - A false positive is possible (an English sentence that begins "No" and
//   mentions stopping, or a Japanese condition such as
//   「ブレーキをしないと止まれません」). It fails toward a person reading the
//   line, never toward silence.
// - A NEW top-level announcement constant must be added to _spokenLines() by
//   hand. The RoadSurfaceState and RecommendedResponse getters are enumerated
//   automatically.
// - JAF's advisory text (japanese_snow_vocabulary) is display text relayed
//   verbatim, and is out of scope here. It carries 厳禁 on braking and
//   stopping, so it must not be spoken or shown while she drives.

import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

// ---- The predicate ----------------------------------------------------------

final RegExp _jaBrakeOrStop = RegExp(r'ブレーキ|制動|停止|止ま|停車');
final RegExp _jaAbsolute = RegExp(r'厳禁|禁止|絶対|てはいけ|てはなら|べからず');
final RegExp _jaNegatedBrakeVerb = RegExp(
    r'ブレーキ(操作)?[をは]?(踏ま|かけ|し|使わ|使用し)ない|止まらない|停止しない|停車しない');

final RegExp _enBrakeOrStop = RegExp(r'\bbrak|\bstop', caseSensitive: false);
final RegExp _enAbsolute = RegExp(
  r'^no\b|\bnever\b|\bforbidden\b|\bprohibited\b|\bstrictly\b|\bmust not\b',
  caseSensitive: false,
);
final RegExp _enNegatedBrakeVerb = RegExp(
  r"\b(do not|don't|never|must not)\s+"
  r'((\w+\s+)?(brake|stop|slam)'
  r'|(use|hit|apply|press|touch)\s+(the\s+)?brakes?)',
  caseSensitive: false,
);

List<String> _sentences(String text, {required bool ja}) => text
    .split(ja ? RegExp(r'(?<=[。！？])') : RegExp(r'(?<=[.!?;])\s+'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// The sentences of [text] that forbid braking or stopping. Empty if none.
List<String> brakingProhibitions(String text, {required bool ja}) => [
      for (final s in _sentences(text, ja: ja))
        if (ja
            ? (_jaBrakeOrStop.hasMatch(s) && _jaAbsolute.hasMatch(s)) ||
                _jaNegatedBrakeVerb.hasMatch(s)
            : (_enBrakeOrStop.hasMatch(s) && _enAbsolute.hasMatch(s)) ||
                _enNegatedBrakeVerb.hasMatch(s))
          s,
    ];

// ---- Controls: the predicate must bite, and must not bite a request ---------

const List<String> _mustFlagJa = [
  '急ハンドル、急ブレーキは厳禁。', // the shipped defect
  '急ブレーキは禁止です。',
  'ブレーキを踏まないでください。',
  '急停止は絶対にしないでください。',
  '発進、停止、カーブで「急」のつく動作は厳禁。', // JAF's own form
  // The plainest way to tell a driver in unexpected snow not to make the stop.
  // Until 2026-09-25 the predicate let all three through.
  '急ブレーキをしないでください。',
  'ブレーキを使わないでください。',
  'ブレーキ操作はしないでください。',
];
const List<String> _mustFlagEn = [
  'No abrupt steering or braking.', // the shipped defect
  'Hard braking is strictly forbidden.',
  'Do not brake hard.',
  'Never slam on the brakes.',
  'abrupt starts, stops, and turns are strictly forbidden.',
  'Do not use the brakes.', // let through until 2026-09-25
  "Don't hit the brakes.", // let through until 2026-09-25
];
const List<String> _mustPassJa = [
  '速度を落とし、急ブレーキ・急ハンドルは避けてください。', // a request
  '急ハンドル・急ブレーキを避け、速度を落としてください。',
  '路面が濡れています。制動距離が伸びます。速度を控えてください。',
  '安全にできるときは、安全な場所での停車も選べます。',
  'ブレーキを緩めないでください。', // negation that keeps her braking
  'ブレーキをしっかり踏んでください。', // し that is not しない
];
const List<String> _mustPassEn = [
  'Reduce speed and avoid abrupt braking or steering.',
  'Wet road surface. Stopping distance increases. Reduce speed.',
  'Keep pressing the brake firmly.',
  'Do not release the brake.',
];

// ---- Every spoken line the package exports ----------------------------------

Map<String, RoadSurfaceAnnouncement> _spokenLines() => {
      for (final s in RoadSurfaceState.values)
        if (s.announcement case final a?) 'RoadSurfaceState.${s.name}': a,
      for (final r in RecommendedResponse.values)
        if (r.announcement case final a?) 'RecommendedResponse.${r.name}': a,
      'invisibleBlackIceAnnouncement': invisibleBlackIceAnnouncement,
      'conditionsUnknownAnnouncement': conditionsUnknownAnnouncement,
      'roadAdvisoryUnmeasuredAnnouncement': roadAdvisoryUnmeasuredAnnouncement,
    };

const String _rule =
    'A spoken line may ask her to avoid abrupt inputs (避けてください / '
    '"avoid"). It must not forbid braking or stopping: 急ブレーキ is also the '
    'emergency stop she may need on ice, so stopping must never sound '
    'forbidden.';

void main() {
  group('the predicate bites (controls)', () {
    for (final s in _mustFlagJa) {
      test('flags: $s', () {
        expect(brakingProhibitions(s, ja: true), isNotEmpty);
      });
    }
    for (final s in _mustFlagEn) {
      test('flags: $s', () {
        expect(brakingProhibitions(s, ja: false), isNotEmpty);
      });
    }
    for (final s in _mustPassJa) {
      test('passes: $s', () {
        expect(brakingProhibitions(s, ja: true), isEmpty);
      });
    }
    for (final s in _mustPassEn) {
      test('passes: $s', () {
        expect(brakingProhibitions(s, ja: false), isEmpty);
      });
    }
  });

  group('no spoken line forbids braking or stopping', () {
    final lines = _spokenLines();

    test('the enumeration reached both black-ice lines', () {
      expect(
        lines.keys,
        containsAll(<String>[
          'invisibleBlackIceAnnouncement',
          'RoadSurfaceState.blackIce',
        ]),
      );
    });

    for (final e in lines.entries) {
      test('${e.key} (ja)', () {
        expect(
          brakingProhibitions(e.value.jaSpokenText, ja: true),
          isEmpty,
          reason: '${e.key}: "${e.value.jaSpokenText}". $_rule',
        );
      });
      test('${e.key} (en)', () {
        expect(
          brakingProhibitions(e.value.enSpokenText, ja: false),
          isEmpty,
          reason: '${e.key}: "${e.value.enSpokenText}". $_rule',
        );
      });
    }
  });
}
