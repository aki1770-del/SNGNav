/// Voice guidance BLoC that reacts to navigation state transitions.
library;

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';

import 'maneuver_speech_formatter.dart';
import 'tts_engine.dart';
import 'voice_guidance_config.dart';
import 'voice_guidance_event.dart';
import 'voice_guidance_state.dart';

class VoiceGuidanceBloc extends Bloc<VoiceGuidanceEvent, VoiceGuidanceState> {
  VoiceGuidanceBloc({
    required TtsEngine ttsEngine,
    required Stream<NavigationState> navigationStateStream,
    VoiceGuidanceConfig config = const VoiceGuidanceConfig(),
    ManeuverSpeechFormatter formatter = const ManeuverSpeechFormatter(),
    DriverProfile? profile,
  })  : _ttsEngine = ttsEngine,
        _config = config,
        _formatter = formatter,
        _profile = profile,
        super(config.enabled
            ? const VoiceGuidanceState.idle()
            : const VoiceGuidanceState(status: VoiceGuidanceStatus.muted)) {
    on<VoiceEnabled>(_onVoiceEnabled);
    on<VoiceDisabled>(_onVoiceDisabled);
    on<NavigationStateObserved>(_onNavigationStateObserved);
    on<ManeuverAnnounced>(_onManeuverAnnounced);
    on<HazardAnnounced>(_onHazardAnnounced);

    _navigationSub = navigationStateStream.listen((navigationState) {
      add(NavigationStateObserved(navigationState: navigationState));
    });

    if (_config.enabled) {
      _initializeTts();
    }
  }

  final TtsEngine _ttsEngine;
  final VoiceGuidanceConfig _config;
  final ManeuverSpeechFormatter _formatter;

  /// Active driver profile (0.5.0). When supplied alongside a
  /// `NavigationState.alertCondition`, the bloc resolves the per-
  /// (condition, profile) action string via
  /// `AlertExplainer.forConditionAndProfile` and speaks that string
  /// at the explainer's locale tag — overriding the raw
  /// [NavigationState.alertMessage] for the hazard branch only.
  /// Null preserves pre-0.5.0 back-compat: hazard branch falls back
  /// to the raw alertMessage.
  final DriverProfile? _profile;

  StreamSubscription<NavigationState>? _navigationSub;

  int? _lastManeuverIndex;
  NavigationStatus? _lastNavigationStatus;
  String? _lastAlertMessage;
  AlertSeverity? _lastAlertSeverity;

  bool get _voiceEnabled => state.status != VoiceGuidanceStatus.muted;

  Future<void> _initializeTts() async {
    await _ttsEngine.setLanguage(_config.languageTag);
    await _ttsEngine.setVolume(_config.volume);
  }

  Future<void> _onVoiceEnabled(
    VoiceEnabled event,
    Emitter<VoiceGuidanceState> emit,
  ) async {
    await _initializeTts();
    emit(state.copyWith(status: VoiceGuidanceStatus.idle));
  }

  Future<void> _onVoiceDisabled(
    VoiceDisabled event,
    Emitter<VoiceGuidanceState> emit,
  ) async {
    await _ttsEngine.stop();
    emit(state.copyWith(status: VoiceGuidanceStatus.muted));
  }

  Future<void> _onNavigationStateObserved(
    NavigationStateObserved event,
    Emitter<VoiceGuidanceState> emit,
  ) async {
    final navigationState = event.navigationState;
    if (!_voiceEnabled) {
      _cacheNavigationMarkers(navigationState);
      return;
    }

    final currentManeuver = navigationState.currentManeuver;
    if (currentManeuver != null &&
        navigationState.currentManeuverIndex != _lastManeuverIndex) {
      final text = _formatter.formatManeuver(
        currentManeuver,
        languageTag: _config.languageTag,
      );
      add(ManeuverAnnounced(text: text));
    }

    final hasArrivedTransition =
        navigationState.status == NavigationStatus.arrived &&
            _lastNavigationStatus != NavigationStatus.arrived;
    if (hasArrivedTransition) {
      final text = _formatter.formatArrival(
        destinationLabel: navigationState.destinationLabel,
        languageTag: _config.languageTag,
      );
      add(ManeuverAnnounced(text: text));
    }

    final hasDeviationTransition =
        navigationState.status == NavigationStatus.deviated &&
            _lastNavigationStatus != NavigationStatus.deviated;
    if (hasDeviationTransition) {
      final deviationMessage =
          _formatter.formatDeviation(languageTag: _config.languageTag);
      add(HazardAnnounced(
        message: deviationMessage,
        severity: AlertSeverity.warning,
      ));
    }

    if (navigationState.alertMessage != null && navigationState.alertSeverity != null) {
      final shouldAnnounceAlert =
          navigationState.alertSeverity!.index >= AlertSeverity.warning.index;
      final alertChanged = navigationState.alertMessage != _lastAlertMessage ||
          navigationState.alertSeverity != _lastAlertSeverity;
      if (shouldAnnounceAlert && alertChanged) {
        // Action-coupled hazard rendering (0.5.0). When the state
        // carries a road-surface condition AND the bloc has a driver
        // profile, the explainer's per-(condition, profile) action
        // string + locale tag override the raw alertMessage. The
        // explainer's localeTag also drives the TTS engine language
        // for this announcement so the EN-locale variant for the
        // foreign-tourist profile speaks in English without the
        // integrator switching the bloc-wide config.
        final condition = navigationState.alertCondition;
        String hazardText;
        String? overrideLocaleTag;
        if (condition != null && _profile != null) {
          final explainer =
              AlertExplainer.forConditionAndProfile(condition, _profile);
          hazardText = _formatter.formatHazard(
            message: explainer.action,
            severity: navigationState.alertSeverity!,
            languageTag: explainer.localeTag,
          );
          overrideLocaleTag = explainer.localeTag;
        } else {
          hazardText = _formatter.formatHazard(
            message: navigationState.alertMessage!,
            severity: navigationState.alertSeverity!,
            languageTag: _config.languageTag,
          );
        }

        if (overrideLocaleTag != null &&
            overrideLocaleTag != _config.languageTag) {
          // Honour the per-condition locale on this announcement.
          // Setting language on the engine takes effect for the
          // subsequent speak call.
          unawaited(_ttsEngine.setLanguage(overrideLocaleTag));
        }

        add(HazardAnnounced(
          message: hazardText,
          severity: navigationState.alertSeverity!,
        ));
      }
    }

    _cacheNavigationMarkers(navigationState);
  }

  Future<void> _onManeuverAnnounced(
    ManeuverAnnounced event,
    Emitter<VoiceGuidanceState> emit,
  ) async {
    if (!_voiceEnabled) return;

    emit(state.copyWith(
      status: VoiceGuidanceStatus.speaking,
      lastSpokenText: event.text,
      lastManeuverIndex: _lastManeuverIndex,
    ));

    await _ttsEngine.speak(event.text);

    emit(state.copyWith(status: VoiceGuidanceStatus.idle));
  }

  Future<void> _onHazardAnnounced(
    HazardAnnounced event,
    Emitter<VoiceGuidanceState> emit,
  ) async {
    if (!_voiceEnabled) return;

    // Hazard announcements interrupt maneuver speech for safety priority.
    await _ttsEngine.stop();

    emit(state.copyWith(
      status: VoiceGuidanceStatus.speaking,
      lastSpokenText: event.message,
      lastHazardMessage: event.message,
    ));

    await _ttsEngine.speak(event.message);

    emit(state.copyWith(status: VoiceGuidanceStatus.idle));
  }

  void _cacheNavigationMarkers(NavigationState state) {
    _lastManeuverIndex = state.currentManeuverIndex;
    _lastNavigationStatus = state.status;
    _lastAlertMessage = state.alertMessage;
    _lastAlertSeverity = state.alertSeverity;
  }

  @override
  Future<void> close() async {
    await _navigationSub?.cancel();
    await _ttsEngine.dispose();
    return super.close();
  }
}
