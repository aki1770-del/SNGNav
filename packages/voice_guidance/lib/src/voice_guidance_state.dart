/// Voice guidance state model.
library;

import 'package:equatable/equatable.dart';

enum VoiceGuidanceStatus {
  idle,
  speaking,
  muted,
}

class VoiceGuidanceState extends Equatable {
  const VoiceGuidanceState({
    required this.status,
    this.lastSpokenText,
    this.lastHazardMessage,
    this.lastManeuverIndex,
  });

  const VoiceGuidanceState.idle()
      : status = VoiceGuidanceStatus.idle,
        lastSpokenText = null,
        lastHazardMessage = null,
        lastManeuverIndex = null;

  final VoiceGuidanceStatus status;
  final String? lastSpokenText;
  final String? lastHazardMessage;
  final int? lastManeuverIndex;

  bool get isMuted => status == VoiceGuidanceStatus.muted;

  VoiceGuidanceState copyWith({
    VoiceGuidanceStatus? status,
    String? lastSpokenText,
    String? lastHazardMessage,
    int? lastManeuverIndex,
  }) {
    return VoiceGuidanceState(
      status: status ?? this.status,
      lastSpokenText: lastSpokenText ?? this.lastSpokenText,
      lastHazardMessage: lastHazardMessage ?? this.lastHazardMessage,
      lastManeuverIndex: lastManeuverIndex ?? this.lastManeuverIndex,
    );
  }

  @override
  List<Object?> get props => [
        status,
        lastSpokenText,
        lastHazardMessage,
        lastManeuverIndex,
      ];
}
