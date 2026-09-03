/// Voice guidance BLoC that reacts to navigation state transitions.
library;

import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:navigation_safety/navigation_safety.dart';
// The pure haptic-cue grammar + severity mapping live in the pure-Dart
// enums package. Aliased because it declares its own `AlertSeverity` (a
// byte-identical copy of the core enum); the bloc bridges core -> enums
// via the exhaustive `_hapticPatternFor` switch below.
import 'package:navigation_safety_enums/navigation_safety_enums.dart' as nse;

import 'haptic_engine.dart';
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
    HapticEngine? hapticEngine,
  }) : _ttsEngine = ttsEngine,
       _config = config,
       _formatter = formatter,
       _profile = profile,
       _glanceBudgetTracker = glanceBudgetTracker,
       _hapticEngine = hapticEngine,
       super(
         config.enabled
             ? const VoiceGuidanceState.idle()
             : const VoiceGuidanceState(status: VoiceGuidanceStatus.muted),
       ) {
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
      _glanceBudgetSub = _glanceBudgetTracker.budgetEvents.listen((_) {
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

  /// Optional tactile (haptic) engine for the accessibility hazard channel
  /// (0.7.0). When supplied, the bloc fires a tactile cue ADDITIVELY beside
  /// the existing TTS speak in the hazard dispatch — off the SAME severity
  /// gate — so a deaf / hard-of-hearing driver (or HER in a roaring-wind
  /// whiteout where speech cannot carry) receives the same hazard warning a
  /// hearing driver gets, via a tactile channel.
  ///
  /// The haptic channel is additive-only: it NEVER gates, delays, or
  /// silences the audio channel. Null preserves pre-0.7.0 back-compat: with
  /// no haptic engine the audio path is byte-for-byte identical.
  final HapticEngine? _hapticEngine;

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
    final remainingRatio = tracker.remainingBudget.inMicroseconds / totalMicros;
    final budgetMultiplier = budgetProfile.paceForRemainingRatio(
      remainingRatio,
    );
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
      final deviationMessage = _formatter.formatDeviation(
        languageTag: _config.languageTag,
      );
      add(
        HazardAnnounced(
          message: deviationMessage,
          severity: AlertSeverity.warning,
        ),
      );
    }

    if (navigationState.alertMessage != null &&
        navigationState.alertSeverity != null) {
      final shouldAnnounceAlert =
          navigationState.alertSeverity!.index >= AlertSeverity.warning.index;
      final alertChanged =
          navigationState.alertMessage != _lastAlertMessage ||
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
          final explainer = AlertExplainer.forConditionAndProfile(
            condition,
            _profile,
          );
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

        // The locale rides on the event; it is NOT set on the engine here.
        // `unawaited(setLanguage(...))` used to sit at this line, and the
        // comment beside it asserted the change "takes effect for the
        // subsequent speak call". It does not: the two are independent
        // futures and the utterance can win.
        add(
          HazardAnnounced(
            message: hazardText,
            severity: navigationState.alertSeverity!,
            localeTag: overrideLocaleTag,
          ),
        );
      }
    }

    _cacheNavigationMarkers(navigationState);
  }

  Future<void> _onManeuverAnnounced(
    ManeuverAnnounced event,
    Emitter<VoiceGuidanceState> emit,
  ) async {
    if (!_voiceEnabled) return;

    emit(
      state.copyWith(
        status: VoiceGuidanceStatus.speaking,
        lastSpokenText: event.text,
        lastManeuverIndex: _lastManeuverIndex,
      ),
    );

    await _ttsEngine.speak(event.text);

    emit(state.copyWith(status: VoiceGuidanceStatus.idle));
  }

  Future<void> _onHazardAnnounced(
    HazardAnnounced event,
    Emitter<VoiceGuidanceState> emit,
  ) async {
    if (!_voiceEnabled) return;

    // Accessibility (0.7.0): fire the tactile cue ADDITIVELY beside the
    // audio, off the SAME severity gate the audio uses, so a deaf /
    // hard-of-hearing driver (or HER in a roaring-wind whiteout) receives
    // the same hazard warning. Fire-and-forget so the haptic channel can
    // NEVER delay, gate, or silence audio; the engine's cue() never throws
    // (honest degradation), so the unawaited future cannot surface an
    // unhandled async error.
    final hapticEngine = _hapticEngine;
    if (hapticEngine != null) {
      unawaited(hapticEngine.cue(_hapticPatternFor(event.severity)));
    }

    // Hazard announcements interrupt maneuver speech for safety priority.
    await _ttsEngine.stop();

    emit(
      state.copyWith(
        status: VoiceGuidanceStatus.speaking,
        lastSpokenText: event.message,
        lastHazardMessage: event.message,
      ),
    );

    // Await the language change BEFORE the utterance, and restore the
    // configured voice after it. Without the restore, one override left the
    // engine on the override locale for the life of the session — measured:
    // Japanese turn text spoken by an English voice, permanently.
    final overrideTag = event.localeTag;
    final needsOverride =
        overrideTag != null && overrideTag != _config.languageTag;
    if (needsOverride) {
      await _ttsEngine.setLanguage(overrideTag);
    }
    try {
      await _ttsEngine.speak(event.message);
    } finally {
      if (needsOverride) {
        await _ttsEngine.setLanguage(_config.languageTag);
      }
    }

    emit(state.copyWith(status: VoiceGuidanceStatus.idle));
  }

  /// Bridge the core [AlertSeverity] the hazard event carries to the pure
  /// enums-package severity, then to its tactile [nse.HapticCuePattern].
  ///
  /// The two `AlertSeverity` declarations (core's and the enums package's)
  /// are byte-identical today but are distinct types; this switch is the
  /// honest bridge. It is exhaustive and compile-checked: if the core enum
  /// ever gains a value this fails to BUILD — fail-loud, never a silent
  /// mismap into the wrong cue. The mapping mirrors the audio severity gate
  /// exactly, so the deaf driver's cue set equals the hearing driver's
  /// warning set.
  nse.HapticCuePattern _hapticPatternFor(AlertSeverity severity) {
    final mapped = switch (severity) {
      AlertSeverity.info => nse.AlertSeverity.info,
      AlertSeverity.warning => nse.AlertSeverity.warning,
      AlertSeverity.critical => nse.AlertSeverity.critical,
    };
    return nse.hapticCueForSeverity(mapped);
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
    await _hapticEngine?.dispose();
    return super.close();
  }
}
