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
    this.localeTag,
  });

  final String message;
  final AlertSeverity severity;

  /// BCP-47 tag this specific announcement must be spoken in, when the
  /// condition's explainer differs from the configured voice.
  ///
  /// It rides on the EVENT rather than being set on the engine beforehand.
  /// Setting the engine outside the handler is fire-and-forget: the language
  /// change and the utterance are two independent futures, and the utterance
  /// can win. Measured on this bloc: the English critical black-ice warning
  /// was spoken by the Japanese engine, with the language change landing
  /// after it. Carrying the tag here makes the ordering structural.
  final String? localeTag;

  @override
  List<Object?> get props => [message, severity, localeTag];
}
