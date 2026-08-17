/// In-drive compound-failure caution advisor — the in-drive counterpart to
/// `pretrip_decision_advisor`.
///
/// Where the pre-trip advisor answers "should I leave?" (and may honestly say
/// *wait*), this answers the strictly different in-drive question — "conditions
/// are degrading while I'm already moving on a snow road; how should I hold the
/// wheel right now?" — and its ceiling is a gentle, reversible *consider
/// stopping*, never *turn back*. The two share no decision surface and no verb.
///
/// It fuses position-trust × what-she-can-see (with advisory severity + speed
/// as escalators) into one honest, immutable caution record. The one
/// intentional non-linearity: position-uncertain AND low-visibility TOGETHER
/// yields the strongest caution — the danger COMPOUNDS.
///
/// Pure Dart — zero runtime dependencies, no Flutter, no IO, no clock, no
/// globals; 32-bit-ARM friendly; one total, deterministic, synchronous pure
/// function ([adviseInDrive]). Advisory-only: it labels the moment; she drives
/// it. See `README.md`.
library;

export 'src/drive_advice.dart';
export 'src/drive_advice_messages.dart';
export 'src/drive_situation.dart';
export 'src/in_drive_advisor.dart';
export 'src/mirror_enums.dart';
