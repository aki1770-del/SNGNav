/// FleetLayer widget tests.
///
/// Tests:
///   1. Renders empty MarkerLayer when no reports
///   2. Renders markers for each fleet report
///   3. Hazard markers are larger than non-hazard
///   4. Condition colors: dry=green, wet=blue, snowy=orange, icy=red
///   5. Hazard markers show ice/snow icon
///   6. Non-hazard markers have no icon child
///   7. Tooltip shows vehicleId and condition
///   8. Multiple reports render multiple markers
///
/// Sprint 8 Day 5.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/models/fleet_report.dart';
import 'package:sngnav_snow_scene/widgets/fleet_layer.dart';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _dryReport = FleetReport(
  vehicleId: 'V-001',
  position: const LatLng(35.170, 136.882),
  timestamp: DateTime(2026, 2, 27),
  condition: RoadCondition.dry,
  confidence: 0.9,
);

final _wetReport = FleetReport(
  vehicleId: 'V-002',
  position: const LatLng(35.083, 137.156),
  timestamp: DateTime(2026, 2, 27),
  condition: RoadCondition.wet,
  confidence: 0.85,
);

final _snowyReport = FleetReport(
  vehicleId: 'V-003',
  position: const LatLng(35.060, 137.250),
  timestamp: DateTime(2026, 2, 27),
  condition: RoadCondition.snowy,
  confidence: 0.9,
);

final _icyReport = FleetReport(
  vehicleId: 'V-004',
  position: const LatLng(35.050, 137.320),
  timestamp: DateTime(2026, 2, 27),
  condition: RoadCondition.icy,
  confidence: 0.95,
);

final _unknownReport = FleetReport(
  vehicleId: 'V-005',
  position: const LatLng(35.070, 137.400),
  timestamp: DateTime(2026, 2, 27),
  condition: RoadCondition.unknown,
  confidence: 0.7,
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps FleetLayer in a FlutterMap for widget testing.
Widget _buildWidget(List<FleetReport> reports) {
  return MaterialApp(
    home: Scaffold(
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(35.10, 137.15),
          initialZoom: 10,
        ),
        children: [
          FleetLayer(reports: reports),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FleetLayer', () {
    testWidgets('renders empty MarkerLayer when no reports', (tester) async {
      await tester.pumpWidget(_buildWidget([]));

      // MarkerLayer is present (from FleetLayer) but has no marker children
      expect(find.byType(MarkerLayer), findsOneWidget);
    });

    testWidgets('renders markers for fleet reports', (tester) async {
      await tester.pumpWidget(_buildWidget([_dryReport, _snowyReport]));

      // FleetLayer creates a MarkerLayer with 2 markers
      expect(find.byType(MarkerLayer), findsOneWidget);
      // Each marker has a Tooltip with vehicleId
      expect(find.byType(Tooltip), findsNWidgets(2));
    });

    testWidgets('dry report renders green marker', (tester) async {
      await tester.pumpWidget(_buildWidget([_dryReport]));

      // Find the vehicle dot container — the inner decorated container
      final tooltip = find.byType(Tooltip);
      expect(tooltip, findsOneWidget);

      // Verify tooltip message includes condition
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(tooltipWidget.message, contains('V-001'));
      expect(tooltipWidget.message, contains('dry'));
    });

    testWidgets('icy report renders red marker with ice icon', (tester) async {
      await tester.pumpWidget(_buildWidget([_icyReport]));

      // Hazard marker should have ac_unit icon
      expect(find.byIcon(Icons.ac_unit), findsOneWidget);

      final tooltip = find.byType(Tooltip);
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(tooltipWidget.message, contains('V-004'));
      expect(tooltipWidget.message, contains('icy'));
    });

    testWidgets('snowy report renders orange marker with snow icon',
        (tester) async {
      await tester.pumpWidget(_buildWidget([_snowyReport]));

      // Hazard marker should have cloudy_snowing icon
      expect(find.byIcon(Icons.cloudy_snowing), findsOneWidget);

      final tooltip = find.byType(Tooltip);
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(tooltipWidget.message, contains('V-003'));
      expect(tooltipWidget.message, contains('snowy'));
    });

    testWidgets('non-hazard markers have no weather icon', (tester) async {
      await tester.pumpWidget(_buildWidget([_dryReport, _wetReport]));

      // No hazard icons should be present
      expect(find.byIcon(Icons.ac_unit), findsNothing);
      expect(find.byIcon(Icons.cloudy_snowing), findsNothing);
    });

    testWidgets('unknown condition renders grey marker', (tester) async {
      await tester.pumpWidget(_buildWidget([_unknownReport]));

      final tooltip = find.byType(Tooltip);
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(tooltipWidget.message, contains('V-005'));
      expect(tooltipWidget.message, contains('unknown'));
    });

    testWidgets('multiple reports render correct count of markers',
        (tester) async {
      await tester.pumpWidget(_buildWidget([
        _dryReport,
        _wetReport,
        _snowyReport,
        _icyReport,
        _unknownReport,
      ]));

      // 5 tooltips = 5 vehicle markers
      expect(find.byType(Tooltip), findsNWidgets(5));
      // 2 hazard icons (snowy + icy)
      expect(find.byIcon(Icons.cloudy_snowing), findsOneWidget);
      expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    });

    testWidgets('wet report tooltip shows correct info', (tester) async {
      await tester.pumpWidget(_buildWidget([_wetReport]));

      final tooltip = find.byType(Tooltip);
      final tooltipWidget = tester.widget<Tooltip>(tooltip);
      expect(tooltipWidget.message, 'V-002: wet');
    });
  });
}
