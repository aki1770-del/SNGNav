// Units contract for the KUKSA end-to-end harness.
//
// WHY THIS EXISTS (OPS-070(B), written before the act):
//
//   A UNIT is a contract between two parties who never meet — whoever fills a
//   VSS leaf, and whoever reads it. On 2026-08-26 those two sides were found to
//   have drifted. `Vehicle.ADAS.ESC.RoadFriction.MostProbable` is PERCENT, range
//   0-100. The app read the wire value as a 0.0-1.0 fraction, so a real ESC
//   reporting 18 on black ice was evaluated as `18.0 < 0.3` — false. The
//   friction limb of the black-ice check could never fire, and that is the ONE
//   limb that speaks BEFORE the car slips; TCS and ABS only speak after grip is
//   already gone. She is the party who finds out.
//
//   The correction landed in lib/ and in test/. It did not land in
//   tool/kuksa_e2e/, the only artifact that proves the path end-to-end against a
//   real broker — and which NOTHING in this repo runs (measured: 0 references to
//   `kuksa_e2e` in any .sh/.yml/.md). Its two friction literals were still
//   fractions, and its VSS overlay still told the broker the leaf was "0.0-1.0".
//   A harness that is never run cannot report that it has gone wrong.
//
//   Unit tests could not have caught this. `vss_adapter_test.dart` and the app
//   decoder suite both pin 18.0 -> 0.18, but they bind a FUNCTION. Neither reads
//   `tool/`, and the harness's literals are read by nothing at all.
//
// WHY A TEST AND NOT A SCRIPT IN scripts/:
//   Measured the same day: 34 scripts in the governance repo were BUILT and
//   NEVER ARMED — no cron row, no hook, no armed caller. A gate that nothing
//   fires is a file, not a loom. CI already runs `flutter test`, so an assertion
//   placed here is armed by construction and needs no new wiring, no registry
//   row and nobody's memory.
//
// HONEST BOUNDS — what this does NOT do:
//   * It reads the harness as TEXT. It does not run it and does not need a
//     broker. It cannot see a wrong value that arrives through a variable.
//   * Non-literal publish arguments (e.g. `base + i`) cannot be evaluated. They
//     are COUNTED and ratcheted, never silently skipped — adding one trips this
//     test and forces a look.
//   * The fraction-shaped check below has one false-positive class: a literal
//     that genuinely means a fraction of one percent. That failure is LOUD.
//     Loud is survivable; the silence this replaces is what shipped.

import 'dart:convert';
import 'dart:io';

import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every VSS path constant the harness may publish to, resolved FROM the SDK
/// itself so a path can never drift out of step with the package. A constant
/// used by the harness and absent here is a hard failure, never a skip.
const Map<String, String> _constToVssPath = <String, String>{
  'kVehicleSpeed': kVehicleSpeed,
  'kRoadFrictionMostProbable': kRoadFrictionMostProbable,
  'kRoadFrictionLowerBound': kRoadFrictionLowerBound,
  'kTcsIsEngaged': kTcsIsEngaged,
  'kAbsIsEngaged': kAbsIsEngaged,
  'kWiperFrontIntensity': kWiperFrontIntensity,
  'kRaindetectionIntensity': kRaindetectionIntensity,
  'kAirTemperature': kAirTemperature,
  'kTirePressureFrontLeft': kTirePressureFrontLeft,
  'kTirePressureFrontRight': kTirePressureFrontRight,
};

/// Publish arguments that are expressions rather than literals, and so cannot be
/// checked by reading the text. RATCHET: this is an exact expectation, so a new
/// unreadable publish site fails here rather than passing unnoticed.
const int _expectedUncheckablePublishSites = 1; // kVehicleSpeed, `base + i`

const String _harnessPath = 'tool/kuksa_e2e/kuksa_e2e.dart';
const String _overlayPath = 'tool/kuksa_e2e/snow_safety_vss.json';
const String _authorityPath = 'tool/kuksa_e2e/vss_authority.json';

/// A missing input is UNMEASURABLE, and unmeasurable is never a pass. This
/// throws rather than returning a default, and is safe to call outside a test
/// body — a load-time failure is still a failure, and still loud.
Map<String, dynamic> _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
        '$path is missing — this contract cannot be measured, and an '
        'unmeasurable contract is not a satisfied one. Regenerate with '
        'tool/kuksa_e2e/refresh_vss_authority.py');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Flatten the overlay into `full.vss.path -> leaf spec`, branches excluded.
Map<String, Map<String, dynamic>> _overlayLeaves(Map<String, dynamic> tree) {
  final out = <String, Map<String, dynamic>>{};
  void walk(Map<String, dynamic> node, String path) {
    final children = node['children'] as Map<String, dynamic>?;
    if (children == null) return;
    children.forEach((name, spec) {
      final here = path.isEmpty ? name : '$path.$name';
      final map = spec as Map<String, dynamic>;
      if (map['type'] == 'branch') {
        walk(map, here);
      } else {
        out[here] = map;
      }
    });
  }

  tree.forEach((root, spec) => walk(spec as Map<String, dynamic>, root));
  return out;
}

void main() {
  final authorityDoc = _readJson(_authorityPath);
  final authority =
      (authorityDoc['leaves'] as Map<String, dynamic>).cast<String, dynamic>();
  final provenance = authorityDoc['_provenance'] as Map<String, dynamic>;

  group('VSS units contract (authority: VSS ${provenance['tag']} '
      '${(provenance['commit'] as String).substring(0, 8)})', () {
    // -----------------------------------------------------------------------
    // LIMB A — our broker overlay must say what VSS says.
    //
    // The overlay is what we load into the REAL databroker. If it declares a
    // leaf differently from upstream VSS, then the broker and the decoder are
    // working from two different contracts and neither of them knows it.
    // -----------------------------------------------------------------------
    test('the broker overlay agrees with upstream VSS on every leaf it declares',
        () {
      final leaves = _overlayLeaves(_readJson(_overlayPath));
      expect(leaves, isNotEmpty,
          reason: 'the overlay declares no leaves — nothing was measured');

      final disagreements = <String>[];
      leaves.forEach((path, spec) {
        final truth = authority[path] as Map<String, dynamic>?;
        if (truth == null) {
          disagreements.add(
              '$path — declared by our overlay but absent from the authority. '
              'Re-run refresh_vss_authority.py, or the leaf is not real VSS.');
          return;
        }
        // A deviation is permitted only when it is WRITTEN DOWN. An absent
        // reason is the failure; a recorded one is a decision someone made.
        final deviation = spec['_vssDeviation'] as String?;
        for (final attr in const ['datatype', 'type', 'unit', 'min', 'max']) {
          final expected = truth[attr]?.toString();
          if (expected == null) continue; // VSS declares nothing to honour
          final actual = spec[attr]?.toString();
          if (actual == expected) continue;
          if (deviation != null && deviation.contains(attr)) continue;
          disagreements.add(
              '$path.$attr — VSS ${provenance['tag']} says "$expected", our '
              'overlay says "${actual ?? '<absent>'}" (${truth['source']})');
        }
      });

      expect(disagreements, isEmpty,
          reason: 'The overlay we hand the real broker contradicts VSS:\n'
              '  ${disagreements.join('\n  ')}\n'
              'Every one of these is a unit or a bound the broker will not '
              'enforce and the decoder assumes.');
    });

    // -----------------------------------------------------------------------
    // LIMB B — every literal the harness publishes must be expressed in the
    // unit its leaf declares.
    //
    // This is the assertion whose absence let the harness keep publishing
    // fractions to a percent leaf after the decoder was corrected.
    // -----------------------------------------------------------------------
    test('every literal the e2e harness publishes is in its leaf\'s VSS unit',
        () {
      final harness = File(_harnessPath);
      expect(harness.existsSync(), isTrue,
          reason: '$_harnessPath is missing — contract unmeasurable, '
              'which is never a pass');
      final source = harness.readAsStringSync();

      final calls = RegExp(r'publishValue\(\s*(\w+)\s*,\s*([^;]+?)\s*\)\s*;')
          .allMatches(source);
      expect(calls, isNotEmpty,
          reason: 'no publishValue call was found in $_harnessPath — the '
              'matcher has gone stale and this test is measuring nothing');

      final violations = <String>[];
      var uncheckable = 0;

      for (final call in calls) {
        final constName = call.group(1)!;
        final argument = call.group(2)!.trim();
        final line = '\n'.allMatches(source.substring(0, call.start)).length + 1;

        final vssPath = _constToVssPath[constName];
        if (vssPath == null) {
          violations.add('$_harnessPath:$line — publishes to unknown constant '
              '`$constName`; add it to _constToVssPath so it can be checked');
          continue;
        }
        final truth = authority[vssPath] as Map<String, dynamic>?;
        if (truth == null) {
          violations.add('$_harnessPath:$line — `$constName` resolves to '
              '$vssPath, which the authority does not carry');
          continue;
        }

        final datatype = truth['datatype'] as String?;
        final unit = truth['unit'] as String?;
        final max = double.tryParse(truth['max']?.toString() ?? '');
        final min = double.tryParse(truth['min']?.toString() ?? '');

        if (argument == 'true' || argument == 'false') {
          if (datatype != 'boolean') {
            violations.add('$_harnessPath:$line — publishes boolean '
                '`$argument` to $vssPath, which VSS declares $datatype');
          }
          continue;
        }

        final value = double.tryParse(argument);
        if (value == null) {
          uncheckable++; // counted, never silently skipped — see ratchet below
          continue;
        }
        if (datatype == 'boolean') {
          violations.add('$_harnessPath:$line — publishes number `$argument` '
              'to $vssPath, which VSS declares boolean');
          continue;
        }
        final isIntegerLeaf =
            datatype != null && RegExp(r'^u?int\d+$').hasMatch(datatype);
        if (isIntegerLeaf && value != value.roundToDouble()) {
          violations.add('$_harnessPath:$line — publishes non-integer '
              '`$argument` to $vssPath, which VSS declares $datatype');
        }
        if (min != null && value < min) {
          violations.add('$_harnessPath:$line — publishes `$argument` to '
              '$vssPath, below the VSS minimum $min');
        }
        if (max != null && value > max) {
          violations.add('$_harnessPath:$line — publishes `$argument` to '
              '$vssPath, above the VSS maximum $max');
        }
        // THE LIMB THAT CATCHES THE FOUNDING DEFECT. A percent leaf whose range
        // runs to 100, handed a non-integer value inside (0,1), is a fraction
        // wearing a percent's clothes — 0.18 meaning "18% grip". It is inside
        // the declared range, so a bounds check alone sails straight past it.
        if (unit == 'percent' &&
            max == 100 &&
            value.abs() > 0 &&
            value.abs() < 1 &&
            value != value.roundToDouble()) {
          violations.add('$_harnessPath:$line — publishes `$argument` to '
              '$vssPath. That leaf is PERCENT 0-100, so this is a FRACTION '
              'where a percent belongs: an ESC on black ice reports about 18, '
              'not 0.18. Write ${(value * 100).toStringAsFixed(0)}.0.');
        }
      }

      expect(violations, isEmpty,
          reason: 'The e2e harness publishes values in the wrong unit:\n'
              '  ${violations.join('\n  ')}');

      // RATCHET, not a waiver: an unreadable publish site is allowed to exist,
      // but a NEW one has to be looked at by a person.
      expect(uncheckable, _expectedUncheckablePublishSites,
          reason: 'The number of publish sites whose argument cannot be read '
              'as a literal changed. This test cannot check those. Read the '
              'new one, satisfy yourself it carries the right unit, then '
              'update _expectedUncheckablePublishSites.');
    });
  });
}
