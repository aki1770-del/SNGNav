library;

enum CoverageTier {
  t1Corridor(
    label: 'T1 corridor',
    defaultMinZoom: 10,
    defaultMaxZoom: 16,
    defaultExpiryDays: 30,
    autoCache: true,
  ),
  t2Metro(
    label: 'T2 metro',
    defaultMinZoom: 9,
    defaultMaxZoom: 15,
    defaultExpiryDays: 90,
  ),
  t3Prefecture(
    label: 'T3 prefecture',
    defaultMinZoom: 7,
    defaultMaxZoom: 13,
    defaultExpiryDays: 90,
  ),
  t4National(
    label: 'T4 national',
    defaultMinZoom: 5,
    defaultMaxZoom: 10,
    defaultExpiryDays: 90,
  );

  const CoverageTier({
    required this.label,
    required this.defaultMinZoom,
    required this.defaultMaxZoom,
    required this.defaultExpiryDays,
    this.autoCache = false,
  });

  final String label;
  final int defaultMinZoom;
  final int defaultMaxZoom;
  final int defaultExpiryDays;
  final bool autoCache;
}
