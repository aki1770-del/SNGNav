/// Weather events — inputs to the WeatherBloc state machine.
///
/// WeatherBloc manages weather condition monitoring. The provider streams
/// condition updates; the BLoC evaluates hazard level and emits state
/// for the weather overlay and safety alert pipeline.
///
/// Same sealed-class pattern as LocationEvent and NavigationEvent.
///
/// Supports the snow scenario with weather-cache integration.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:equatable/equatable.dart';

sealed class WeatherEvent extends Equatable {
  const WeatherEvent();

  @override
  List<Object?> get props => [];
}

/// Start monitoring weather conditions.
///
/// Dispatched when the app initializes or navigation begins.
/// WeatherBloc subscribes to the WeatherProvider stream.
class WeatherMonitorStarted extends WeatherEvent {
  const WeatherMonitorStarted();
}

/// Stop monitoring weather conditions.
///
/// Dispatched when the app backgrounded or navigation ends.
class WeatherMonitorStopped extends WeatherEvent {
  const WeatherMonitorStopped();
}

/// A new weather condition was received from the provider.
///
/// Internal event — dispatched by WeatherBloc when the provider stream
/// emits. Not dispatched by widgets directly.
class WeatherConditionReceived extends WeatherEvent {
  final WeatherCondition condition;

  const WeatherConditionReceived(this.condition);

  @override
  List<Object?> get props => [condition];
}

/// The weather provider reported an error.
class WeatherErrorOccurred extends WeatherEvent {
  final String message;

  const WeatherErrorOccurred(this.message);

  @override
  List<Object?> get props => [message];
}
