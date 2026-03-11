/// Threshold configuration for score and environmental safety posture.
library;

class NavigationSafetyConfig {
  final double safeScoreFloor;
  final double infoScoreFloor;
  final double warningScoreFloor;

  final int infoTemperatureCelsius;
  final int warningTemperatureCelsius;
  final int criticalTemperatureCelsius;

  final int infoVisibilityMeters;
  final int warningVisibilityMeters;
  final int criticalVisibilityMeters;

  const NavigationSafetyConfig({
    this.safeScoreFloor = 0.80,
    this.infoScoreFloor = 0.50,
    this.warningScoreFloor = 0.30,
    this.infoTemperatureCelsius = 3,
    this.warningTemperatureCelsius = 0,
    this.criticalTemperatureCelsius = -5,
    this.infoVisibilityMeters = 1000,
    this.warningVisibilityMeters = 200,
    this.criticalVisibilityMeters = 50,
  }) : assert(safeScoreFloor >= 0 && safeScoreFloor <= 1),
       assert(infoScoreFloor >= 0 && infoScoreFloor <= 1),
       assert(warningScoreFloor >= 0 && warningScoreFloor <= 1),
       assert(safeScoreFloor >= infoScoreFloor),
       assert(infoScoreFloor >= warningScoreFloor);
}