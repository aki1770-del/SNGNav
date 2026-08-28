import 'dart:convert';

/// Re-shapes a **legacy-schema** JMA warning fixture into the **r8** wire
/// shape the provider reads from 0.7.0, so provider tests written before the
/// 2026-05-29 migration keep testing what they were written to test —
/// border union, timeout isolation, incomplete-read signalling, dedup,
/// staleness — rather than the wire format, which has its own dedicated tests
/// in `jma_r8_warning_test.dart`.
///
/// ⚑ **The legacy fixtures are deliberately NOT rewritten on disk.** Several
/// tests feed them straight to `parseJmaFeed` / `parseJmaWarningJson`, which
/// still parse the legacy schema and must keep being exercised against a real
/// legacy document — that parser is what proves the two schemas can never be
/// silently confused. Only the bytes that travel through an HTTP mock are
/// converted, at the mock boundary, where the wire format actually lives.
///
/// Anything that is not a legacy-shaped object — an r8 list, a malformed
/// fixture that is malformed on purpose — passes through untouched.
String toR8IfLegacy(String body) {
  final dynamic decoded;
  try {
    decoded = json.decode(body);
  } on FormatException {
    return body;
  }
  if (decoded is! Map<String, dynamic>) return body;
  if (!decoded.containsKey('areaTypes')) return body;

  List<Map<String, dynamic>> itemsFrom(int index) {
    final ats = decoded['areaTypes'];
    if (ats is! List || ats.length <= index) return <Map<String, dynamic>>[];
    final at = ats[index];
    if (at is! Map) return <Map<String, dynamic>>[];
    final areas = at['areas'];
    if (areas is! List) return <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final a in areas)
        if (a is Map)
          <String, dynamic>{
            'areaCode': a['code'],
            'kinds': <dynamic>[
              for (final w
                  in (a['warnings'] is List
                      ? a['warnings'] as List
                      : const <dynamic>[]))
                if (w is Map)
                  <String, dynamic>{'code': w['code'], 'status': w['status']},
            ],
          },
    ];
  }

  return json.encode(<dynamic>[
    <String, dynamic>{
      'reportDatetime': decoded['reportDatetime'],
      'publishingOffice': decoded['publishingOffice'],
      'headlineText': decoded['headlineText'],
      'dataTypeCode': 'VPWW53',
      'warning': <String, dynamic>{
        'class10Items': itemsFrom(0),
        'class20Items': itemsFrom(1),
      },
    },
  ]);
}
