@TestOn('vm')
library;

import 'dart:mirrors';

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:test/test.dart';

/// Tokens that would turn this PUBLIC-WEATHER-AT-A-PLACE read into a person
/// watch (見守り-by-proxy) or an over-claim. NONE may appear in any area chip.
const _forbidden = <String>[
  'passable',
  'open',
  'closed',
  'road status',
  'route status',
  'route', // substring-covers 'route status'; no area-* output contains it
  '通行',
  '通行止め',
  '経路',
  'Mom',
  'お母さん',
  'arrived',
  '到着',
  'is she',
  'safe?',
  '無事',
  '見守り',
  'presence',
];

/// Every output an area-* method can produce, for one locale table.
List<String> _allAreaOutputs(PretripMessages m) => [
      m.areaOfficialWarning('大雪警報'),
      m.areaOfficialWarning('Heavy snow warning'),
      m.areaNoOfficialWarning(),
      m.areaWarningCheckUnavailable(),
      for (final b in HourHazard.values) m.areaHazardChip(b),
      for (final b in HourHazard.values) m.areaHazardBand(b),
      m.areaForecastNotCovered(),
      m.areaMeasuredVisibility(80, '秋田', 5),
      m.areaNoMeasuredVisibility(),
    ];

void main() {
  group('vocabulary gate — no person/road-status token in any area chip', () {
    for (final entry in {'en': PretripMessages.en, 'ja': PretripMessages.ja}
        .entries) {
      test('locale ${entry.key}', () {
        for (final out in _allAreaOutputs(entry.value)) {
          for (final bad in _forbidden) {
            expect(out.contains(bad), isFalse,
                reason: 'area chip "$out" must not contain forbidden "$bad"');
          }
        }
      });
    }
  });

  test('structural no-person: AreaConditionRead exposes ONLY the 8 place fields',
      () {
    final cm = reflectClass(AreaConditionRead);
    final fields = <String>{
      for (final d in cm.declarations.values)
        if (d is VariableMirror && !d.isStatic)
          MirrorSystem.getName(d.simpleName),
    };

    expect(
      fields,
      {
        'areaHazard',
        'forecastCovered',
        'officialWarningVerbatim',
        'warningCheckAvailable',
        'measuredVisibilityMeters',
        'visibilityStationName',
        'visibilityDistanceKm',
        'areaLabel',
      },
    );

    // No person/presence/arrival/location/device field, and no
    // suggestion/strength/recommendation/verdict field.
    for (final banned in const [
      'person',
      'presence',
      'arrival',
      'arrived',
      'location',
      'device',
      'suggestedDelay',
      'strength',
      'recommendation',
      'verdict',
    ]) {
      expect(fields.any((f) => f.toLowerCase().contains(banned.toLowerCase())),
          isFalse,
          reason: 'AreaConditionRead must not carry a "$banned" field');
    }
  });
}
