import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_nws/condition_aggregator_nws.dart';
import 'package:noaa_nws_adapter/noaa_nws_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('mapWinterAlertToAdvisory severity gradient', () {
    WinterAlert alertWithSeverity(AlertSeverity s) => WinterAlert(
          event: 'Winter Storm Warning',
          severity: s,
          certainty: AlertCertainty.likely,
          urgency: AlertUrgency.expected,
          areaDesc: 'Towner; Cavalier; Benson',
          effective: DateTime.utc(2026, 5, 3, 0, 0),
          expires: DateTime.utc(2026, 5, 3, 12, 0),
          headline: 'h',
          description: 'd',
          instruction: 'i',
          status: AlertStatus.actual,
          messageType: AlertMessageType.alert,
          senderName: 'NWS Grand Forks ND',
        );

    test('all five severity levels map to interface enum', () {
      expect(mapWinterAlertToAdvisory(alertWithSeverity(AlertSeverity.minor))
          .severity, AdvisorySeverity.minor);
      expect(mapWinterAlertToAdvisory(alertWithSeverity(AlertSeverity.moderate))
          .severity, AdvisorySeverity.moderate);
      expect(mapWinterAlertToAdvisory(alertWithSeverity(AlertSeverity.severe))
          .severity, AdvisorySeverity.severe);
      expect(mapWinterAlertToAdvisory(alertWithSeverity(AlertSeverity.extreme))
          .severity, AdvisorySeverity.extreme);
      expect(mapWinterAlertToAdvisory(alertWithSeverity(AlertSeverity.unknown))
          .severity, AdvisorySeverity.unknown);
    });

    test('high-impact identification preserved through mapping', () {
      final extreme =
          mapWinterAlertToAdvisory(alertWithSeverity(AlertSeverity.extreme));
      final moderate =
          mapWinterAlertToAdvisory(alertWithSeverity(AlertSeverity.moderate));
      expect(extreme.isHighImpact, isTrue);
      expect(moderate.isHighImpact, isFalse);
    });
  });

  group('mapWinterAlertToAdvisory area + verbatim wording', () {
    test('areaDesc preserved verbatim', () {
      final a = WinterAlert(
        event: 'Blizzard Warning',
        severity: AlertSeverity.severe,
        certainty: AlertCertainty.observed,
        urgency: AlertUrgency.immediate,
        areaDesc: 'Towner; Cavalier; Benson; Ramsey; Pierce; Wells; '
            'Eddy; Foster; Stutsman; LaMoure; Logan; McIntosh',
        effective: null,
        expires: null,
        headline: 'Blizzard Warning issued by NWS Grand Forks ND',
        description: 'Whiteout conditions expected.',
        instruction: 'Travel is strongly discouraged.',
        status: AlertStatus.actual,
        messageType: AlertMessageType.alert,
        senderName: 'NWS Grand Forks ND',
      );
      final mapped = mapWinterAlertToAdvisory(a);
      expect(mapped.source, AdvisorySource.nwsUnitedStates);
      expect(mapped.eventClass, 'Blizzard Warning');
      expect(
          mapped.areaDescription,
          'Towner; Cavalier; Benson; Ramsey; Pierce; Wells; '
          'Eddy; Foster; Stutsman; LaMoure; Logan; McIntosh');
      expect(mapped.headline,
          'Blizzard Warning issued by NWS Grand Forks ND');
      expect(mapped.description, 'Whiteout conditions expected.');
    });
  });

  group('mapWinterAlertToAdvisory effective + expires windows', () {
    test('non-null effective + expires preserved exactly', () {
      final eff = DateTime.utc(2026, 5, 3, 6, 0);
      final exp = DateTime.utc(2026, 5, 4, 0, 0);
      final a = WinterAlert(
        event: 'Ice Storm Warning',
        severity: AlertSeverity.severe,
        certainty: AlertCertainty.likely,
        urgency: AlertUrgency.expected,
        areaDesc: 'Area-X',
        effective: eff,
        expires: exp,
        headline: 'h',
        description: 'd',
        instruction: 'i',
        status: AlertStatus.actual,
        messageType: AlertMessageType.alert,
        senderName: 'NWS Office',
      );
      final mapped = mapWinterAlertToAdvisory(a);
      expect(mapped.effective, equals(eff));
      expect(mapped.expires, equals(exp));
      expect(mapped.isExpiredAt(DateTime.utc(2026, 5, 4, 6)), isTrue);
      expect(mapped.isExpiredAt(DateTime.utc(2026, 5, 3, 12)), isFalse);
    });

    test('null effective + null expires preserved (CAP allows omission)', () {
      final a = WinterAlert(
        event: 'Freeze Warning',
        severity: AlertSeverity.moderate,
        certainty: AlertCertainty.likely,
        urgency: AlertUrgency.expected,
        areaDesc: 'Area-Y',
        effective: null,
        expires: null,
        headline: 'h',
        description: 'd',
        instruction: 'i',
        status: AlertStatus.actual,
        messageType: AlertMessageType.alert,
        senderName: 'NWS Office',
      );
      final mapped = mapWinterAlertToAdvisory(a);
      expect(mapped.effective, isNull);
      expect(mapped.expires, isNull);
      expect(mapped.isExpiredAt(DateTime.utc(2099, 1, 1)), isFalse);
    });
  });

  group('mapWinterAlertToAdvisory certainty + urgency mapping', () {
    test('certainty levels map directly', () {
      WinterAlert mk(AlertCertainty c) => WinterAlert(
            event: 'Winter Storm Warning',
            severity: AlertSeverity.severe,
            certainty: c,
            urgency: AlertUrgency.expected,
            areaDesc: 'a',
            effective: null,
            expires: null,
            headline: 'h',
            description: 'd',
            instruction: 'i',
            status: AlertStatus.actual,
            messageType: AlertMessageType.alert,
            senderName: 'NWS',
          );
      expect(mapWinterAlertToAdvisory(mk(AlertCertainty.observed)).certainty,
          AdvisoryCertainty.observed);
      expect(mapWinterAlertToAdvisory(mk(AlertCertainty.likely)).certainty,
          AdvisoryCertainty.likely);
      expect(mapWinterAlertToAdvisory(mk(AlertCertainty.possible)).certainty,
          AdvisoryCertainty.possible);
      expect(mapWinterAlertToAdvisory(mk(AlertCertainty.unlikely)).certainty,
          AdvisoryCertainty.unlikely);
      expect(mapWinterAlertToAdvisory(mk(AlertCertainty.unknown)).certainty,
          AdvisoryCertainty.unknown);
    });

    test('urgency levels map directly', () {
      WinterAlert mk(AlertUrgency u) => WinterAlert(
            event: 'Winter Storm Warning',
            severity: AlertSeverity.severe,
            certainty: AlertCertainty.likely,
            urgency: u,
            areaDesc: 'a',
            effective: null,
            expires: null,
            headline: 'h',
            description: 'd',
            instruction: 'i',
            status: AlertStatus.actual,
            messageType: AlertMessageType.alert,
            senderName: 'NWS',
          );
      expect(mapWinterAlertToAdvisory(mk(AlertUrgency.immediate)).urgency,
          AdvisoryUrgency.immediate);
      expect(mapWinterAlertToAdvisory(mk(AlertUrgency.expected)).urgency,
          AdvisoryUrgency.expected);
      expect(mapWinterAlertToAdvisory(mk(AlertUrgency.future)).urgency,
          AdvisoryUrgency.future);
      expect(mapWinterAlertToAdvisory(mk(AlertUrgency.past)).urgency,
          AdvisoryUrgency.past);
      expect(mapWinterAlertToAdvisory(mk(AlertUrgency.unknown)).urgency,
          AdvisoryUrgency.unknown);
    });
  });

  group('NwsAdvisoryProvider construction + init', () {
    test('source identifies as nwsUnitedStates', () {
      final p = NwsAdvisoryProvider(
        userAgent: '(test.example, contact@test.example)',
      );
      expect(p.source, AdvisorySource.nwsUnitedStates);
      p.close();
    });

    test('init is no-op (does not throw)', () async {
      final p = NwsAdvisoryProvider(
        userAgent: '(test.example, contact@test.example)',
      );
      await p.init();
      // calling twice also fine
      await p.init();
      p.close();
    });
  });
}
