/// Voice guidance events.
library;

import 'package:equatable/equatable.dart';
import 'package:navigation_safety/navigation_safety.dart';

sealed class VoiceGuidanceEvent extends Equatable {
  const VoiceGuidanceEvent();

  @override
  List<Object?> get props => const [];
}

class VoiceEnabled extends VoiceGuidanceEvent {
  const VoiceEnabled();
}

class VoiceDisabled extends VoiceGuidanceEvent {
  const VoiceDisabled();
}

class NavigationStateObserved extends VoiceGuidanceEvent {
  const NavigationStateObserved({required this.navigationState});

  final NavigationState navigationState;

  @override
  List<Object?> get props => [navigationState];
}

class ManeuverAnnounced extends VoiceGuidanceEvent {
  const ManeuverAnnounced({required this.text});

  final String text;

  @override
  List<Object?> get props => [text];
}

class HazardAnnounced extends VoiceGuidanceEvent {
  const HazardAnnounced({
    required this.message,
    required this.severity,
  });

  final String message;
  final AlertSeverity severity;

  @override
  List<Object?> get props => [message, severity];
}
