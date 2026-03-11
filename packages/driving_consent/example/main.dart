import 'package:driving_consent/driving_consent.dart';

Future<void> main() async {
  final service = InMemoryConsentService();

  final initial = await service.getConsent(ConsentPurpose.fleetLocation);
  print('initial: ${initial.status.name} '
      '(effective=${initial.isEffectivelyGranted})');

  await service.grant(ConsentPurpose.fleetLocation, Jurisdiction.appi);
  final granted = await service.getConsent(ConsentPurpose.fleetLocation);
  print('after grant: ${granted.status.name} '
      '(effective=${granted.isEffectivelyGranted})');

  await service.revoke(ConsentPurpose.fleetLocation);
  final revoked = await service.getConsent(ConsentPurpose.fleetLocation);
  print('after revoke: ${revoked.status.name} '
      '(effective=${revoked.isEffectivelyGranted})');

  await service.dispose();
}