/// Consent events — inputs to the ConsentBloc state machine.
///
/// ConsentBloc manages the consent gate lifecycle:
///   load all → grant per-purpose → revoke per-purpose
///
/// Consent is explicit, revocable, and purpose-scoped.
library;

import 'package:equatable/equatable.dart';

import '../models/consent_record.dart';

sealed class ConsentEvent extends Equatable {
  const ConsentEvent();

  @override
  List<Object?> get props => [];
}

/// Load all consent records from the service.
///
/// Dispatched at app startup to populate the consent state.
class ConsentLoadRequested extends ConsentEvent {
  const ConsentLoadRequested();
}

/// Grant consent for a specific purpose under a jurisdiction.
///
/// Dispatched when the driver explicitly opts in.
class ConsentGrantRequested extends ConsentEvent {
  final ConsentPurpose purpose;
  final Jurisdiction jurisdiction;

  const ConsentGrantRequested({
    required this.purpose,
    required this.jurisdiction,
  });

  @override
  List<Object?> get props => [purpose, jurisdiction];
}

/// Revoke consent for a specific purpose.
///
/// Dispatched when the driver explicitly opts out.
/// The consent gate closes — data flow stops (Jidoka).
class ConsentRevokeRequested extends ConsentEvent {
  final ConsentPurpose purpose;

  const ConsentRevokeRequested({required this.purpose});

  @override
  List<Object?> get props => [purpose];
}
