/// Runtime config for voice guidance behavior.
library;

import 'package:equatable/equatable.dart';

class VoiceGuidanceConfig extends Equatable {
  const VoiceGuidanceConfig({
    this.enabled = true,
    this.languageTag = 'ja-JP',
    this.volume = 1.0,
    this.maneuverLeadDistanceMeters = 120.0,
    this.minAnnouncementIntervalSeconds = 3,
  })  : assert(volume >= 0.0 && volume <= 1.0),
        assert(maneuverLeadDistanceMeters >= 0),
        assert(minAnnouncementIntervalSeconds >= 0);

  final bool enabled;
  final String languageTag;
  final double volume;
  final double maneuverLeadDistanceMeters;
  final int minAnnouncementIntervalSeconds;

  VoiceGuidanceConfig copyWith({
    bool? enabled,
    String? languageTag,
    double? volume,
    double? maneuverLeadDistanceMeters,
    int? minAnnouncementIntervalSeconds,
  }) {
    return VoiceGuidanceConfig(
      enabled: enabled ?? this.enabled,
      languageTag: languageTag ?? this.languageTag,
      volume: volume ?? this.volume,
      maneuverLeadDistanceMeters:
          maneuverLeadDistanceMeters ?? this.maneuverLeadDistanceMeters,
      minAnnouncementIntervalSeconds:
          minAnnouncementIntervalSeconds ?? this.minAnnouncementIntervalSeconds,
    );
  }

  @override
  List<Object?> get props => [
        enabled,
        languageTag,
        volume,
        maneuverLeadDistanceMeters,
        minAnnouncementIntervalSeconds,
      ];
}
