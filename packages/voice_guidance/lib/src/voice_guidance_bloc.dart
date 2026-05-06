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
    GlanceBudgetTracker? glanceBudgetTracker,
  })  : _ttsEngine = ttsEngine,
        _config = config,
        _formatter = formatter,
        _profile = profile,
        _glanceBudgetTracker = glanceBudgetTracker,
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

    // 0.6.0: subscribe to GlanceBudgetTracker.budgetEvents when both
    // an integrator-supplied tracker and a non-null
    // `config.budgetAwarePace` are provided. On each budget event,
    // recompute the effective TTS rate and apply it. The subscription
    // is opt-in: a null tracker or null `budgetAwarePace` preserves
    // pre-0.6.0 back-compat (no extra subscription, no extra rate
    // changes beyond the per-profile baseline applied at init).
    if (_glanceBudgetTracker != null && _config.budgetAwarePace != null) {
      _glanceBudgetSub =
          _glanceBudgetTracker.budgetEvents.listen((_) {
        unawaited(_applyBudgetAwareRate());
      });
    }

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

  /// Optional integrator-supplied off-road glance budget tracker
  /// (0.6.0). When supplied alongside a non-null
  /// `config.budgetAwarePace`, the bloc subscribes to budget events
  /// and modulates the effective TTS speaking-rate as the budget is
  /// consumed. Caution-add-only: the modulation can only SLOW speech
  /// (pace ≤ 1.0× baseline); never speeds up.
  final GlanceBudgetTracker? _glanceBudgetTracker;

  StreamSubscription<NavigationState>? _navigationSub;
  StreamSubscription<GlanceBudgetEvent>? _glanceBudgetSub;

  int? _lastManeuverIndex;
  NavigationStatus? _lastNavigationStatus;
  String? _lastAlertMessage;
  AlertSeverity? _lastAlertSeverity;

  bool get _voiceEnabled => state.status != VoiceGuidanceStatus.muted;

  Future<void> _initializeTts() async {
    await _ttsEngine.setLanguage(_config.languageTag);
    await _ttsEngine.setVolume(_config.volume);
    await _ttsEngine.setSpeechRate(_effectiveSpeakingRate());
  }

  /// Compute the effective TTS speaking-rate, composing the per-profile
  /// baseline (`config.speakingRate`) with the budget-aware multiplier
  /// when 0.6.0 budget-aware pace is active.
  ///
  /// Caution-add-only: the budget-aware multiplier is bounded above by
  /// `BudgetAwarePaceProfile.maxPace` (≤ 1.0) by construction asserts
  /// in the profile; the composed effective rate is therefore always
  /// ≤ baseline `config.speakingRate`. The modulation only SLOWS;
  /// never speeds up.
  double _effectiveSpeakingRate() {
    final budgetProfile = _config.budgetAwarePace;
    final tracker = _glanceBudgetTracker;
    if (budgetProfile == null || tracker == null) {
      return _config.speakingRate;
    }
    final totalMicros = tracker.totalBudget.inMicroseconds;
    if (totalMicros <= 0) return _config.speakingRate;
    final remainingRatio =
        tracker.remainingBudget.inMicroseconds / totalMicros;
    final budgetMultiplier =
        budgetProfile.paceForRemainingRatio(remainingRatio);
    return _config.speakingRate * budgetMultiplier;
  }

  /// Apply the budget-aware effective rate to the TTS engine. Called
  /// from the budget-events subscription when the budget changes.
  Future<void> _applyBudgetAwareRate() async {
    if (!_voiceEnabled) return;
    await _ttsEngine.setSpeechRate(_effectiveSpeakingRate());
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
    await _glanceBudgetSub?.cancel();
    await _ttsEngine.dispose();
    return super.close();
  }
}
