import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:sngnav_snow_scene/widgets/hazard_zone_layer.dart';

void main() {
  final now = DateTime.now();

  HazardZone makeZone({
    HazardSeverity severity = HazardSeverity.icy,
    int reportCount = 2,
    double radiusMeters = 1000,
  }) {
    return HazardZone(
      center: const LatLng(35.05, 137.25),
      radiusMeters: radiusMeters,
      severity: severity,
      reports: List.generate(
        reportCount,
        (i) => FleetReport(
          vehicleId: 'v$i',
          position: const LatLng(35.05, 137.25),
          timestamp: now,
          condition: severity == HazardSeverity.icy
              ? RoadCondition.icy
              : RoadCondition.snowy,
        ),
      ),
    );
  }

  Widget buildLayer(List<HazardZone> zones) {
    return MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          options: const MapOptions(
            initialCenter: LatLng(35.05, 137.25),
            initialZoom: 12,
          ),
          children: [
            HazardZoneLayer(zones: zones),
          ],
        ),
      ),
    );
  }

  group('HazardZoneLayer', () {
    testWidgets('renders nothing for empty zones', (tester) async {
      await tester.pumpWidget(buildLayer([]));
      // Should render SizedBox.shrink, no CircleLayer.
      expect(find.byType(CircleLayer), findsNothing);
      expect(find.byType(MarkerLayer), findsNothing);
    });

    testWidgets('renders CircleLayer for zones', (tester) async {
      final zones = [makeZone()];
      await tester.pumpWidget(buildLayer(zones));
      expect(find.byType(CircleLayer), findsOneWidget);
    });

    testWidgets('renders MarkerLayer for zone centers', (tester) async {
      final zones = [makeZone()];
      await tester.pumpWidget(buildLayer(zones));
      // MarkerLayer for center icons.
      expect(find.byType(MarkerLayer), findsOneWidget);
    });

    testWidgets('renders ice icon for icy zones', (tester) async {
      final zones = [makeZone(severity: HazardSeverity.icy)];
      await tester.pumpWidget(buildLayer(zones));
      expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    });

    testWidgets('renders snow icon for snowy zones', (tester) async {
      final zones = [makeZone(severity: HazardSeverity.snowy)];
      await tester.pumpWidget(buildLayer(zones));
      expect(find.byIcon(Icons.cloudy_snowing), findsOneWidget);
    });

    testWidgets('shows vehicle count badge for multi-vehicle zones',
        (tester) async {
      final zones = [makeZone(reportCount: 3)];
      await tester.pumpWidget(buildLayer(zones));
      // Badge shows "3" for 3 unique vehicles.
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides vehicle count badge for single-vehicle zones',
        (tester) async {
      final zones = [makeZone(reportCount: 1)];
      await tester.pumpWidget(buildLayer(zones));
      // No badge — vehicleCount is 1.
      expect(find.text('1'), findsNothing);
    });

    testWidgets('renders multiple zones', (tester) async {
      final zones = [
        makeZone(severity: HazardSeverity.icy),
        HazardZone(
          center: const LatLng(35.10, 137.30),
          radiusMeters: 800,
          severity: HazardSeverity.snowy,
          reports: [
            FleetReport(
              vehicleId: 'v10',
              position: const LatLng(35.10, 137.30),
              timestamp: now,
              condition: RoadCondition.snowy,
            ),
          ],
        ),
      ];
      await tester.pumpWidget(buildLayer(zones));
      // Both icons present.
      expect(find.byIcon(Icons.ac_unit), findsOneWidget);
      expect(find.byIcon(Icons.cloudy_snowing), findsOneWidget);
    });
  });
}
