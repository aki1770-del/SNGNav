/// In-app TYPED-PLACE ENTRY for the family-thread destination area.
///
/// WHY this exists (mission anchor — D3 worst-case / PHIL-001 Driver Test): the
/// destination-area read shipped behind build-time `PRETRIP_DEST_*` dart-defines
/// an end driver can never set. This is the minimal in-app surface that lets HER
/// — the driver, a daughter — set her mother's-area destination PLACE herself,
/// completing the family-thread reach. It is a PLACE entry; it watches NO person.
///
/// DIGNITY BOUNDARIES (binding): the entry source is ONLY HER-typed lat/lon OR
/// HER selection from the offline curated JMA prefecture list. There is NO
/// import of any contact list, device-location, person-locating, geo-fencing, or
/// proximity API — and there is NO online geocoder (offline-first, D3
/// worst-case). The label is a place name SHE types; it is never seeded with a
/// person or relationship word. Resolution is prefecture-level (coarse),
/// disclosed as such — never town-level, never an arrival/passable status.
library;

import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:flutter/material.dart';

import '../services/saved_place_store.dart';
import 'briefing_strings.dart';

/// The always-visible tile on the pre-trip surface that lets the driver SET or
/// CHANGE (and remove) the destination area. It frames a PLACE, never a person.
class DestinationEntryTile extends StatelessWidget {
  const DestinationEntryTile({
    super.key,
    required this.strings,
    required this.hasPlace,
    required this.placeLabel,
    required this.forecastEnabled,
    required this.onEdit,
    required this.onClear,
  });

  final BriefingStrings strings;

  /// Whether a destination area is currently set.
  final bool hasPlace;

  /// The current place label (may be empty when the area was set without a
  /// typed name); shown only when [hasPlace].
  final String placeLabel;

  /// Whether the live forecast is enabled for this build. When false, the area
  /// read cannot deliver, so the tile says so honestly rather than implying it.
  final bool forecastEnabled;

  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final title = hasPlace
        ? (placeLabel.isNotEmpty
            ? '${strings.editDestinationAreaButton} · $placeLabel'
            : strings.editDestinationAreaButton)
        : strings.setDestinationAreaButton;

    // Honest subtitle: the local-only disavowal always; the forecast-off caveat
    // when the live source is not enabled for this build.
    final subtitle = forecastEnabled
        ? strings.placeEntryLocalOnlyNote
        : '${strings.placeEntryLocalOnlyNote}\n${strings.placeEntryForecastOffNote}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.place_outlined),
        title: Text(title),
        subtitle: Text(subtitle),
        isThreeLine: !forecastEnabled,
        onTap: onEdit,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: hasPlace
                  ? strings.editDestinationAreaButton
                  : strings.setDestinationAreaButton,
              onPressed: onEdit,
            ),
            if (hasPlace)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: strings.placeEntryClear,
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

/// The two-mode entry mode: a prefecture pick (coarse, offline list) or typed
/// coordinates.
enum _EntryMode { prefecture, coordinates }

/// Opens the place-entry dialog and resolves to the chosen [SavedPlace], or null
/// if the driver cancels. [initial] pre-fills the dialog when editing.
Future<SavedPlace?> showPlaceEntryDialog(
  BuildContext context, {
  required BriefingStrings strings,
  SavedPlace? initial,
}) {
  return showDialog<SavedPlace>(
    context: context,
    builder: (context) => PlaceEntryDialog(strings: strings, initial: initial),
  );
}

/// The destination-area entry dialog. A 2-mode toggle: a prefecture pick over
/// the offline curated JMA list, or typed coordinates with an optional place
/// name. No online geocoder; no person signal.
class PlaceEntryDialog extends StatefulWidget {
  const PlaceEntryDialog({
    super.key,
    required this.strings,
    this.initial,
  });

  final BriefingStrings strings;
  final SavedPlace? initial;

  @override
  State<PlaceEntryDialog> createState() => _PlaceEntryDialogState();
}

class _PlaceEntryDialogState extends State<PlaceEntryDialog> {
  _EntryMode _mode = _EntryMode.prefecture;
  String? _prefectureCode;

  late final TextEditingController _latCtl;
  late final TextEditingController _lonCtl;
  late final TextEditingController _labelCtl;

  // Set when a save attempt fails validation, so the dialog shows the invalid-
  // coordinate note and does NOT pop.
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _latCtl = TextEditingController(text: init != null ? '${init.lat}' : '');
    _lonCtl = TextEditingController(text: init != null ? '${init.lon}' : '');
    // The label is a PLACE name the driver types. It is NEVER seeded with a
    // person/relationship default — only an existing typed label is restored.
    _labelCtl = TextEditingController(text: init?.label ?? '');
    // Default to the prefecture picker (coarse list). If editing, coordinates
    // are the faithful surface for an arbitrary saved point.
    _mode = init != null ? _EntryMode.coordinates : _EntryMode.prefecture;
  }

  @override
  void dispose() {
    _latCtl.dispose();
    _lonCtl.dispose();
    _labelCtl.dispose();
    super.dispose();
  }

  /// Centroid of a prefecture bounding box, read app-side (NO package edit, NO
  /// publish): lat = (south+north)/2, lon = (west+east)/2.
  static ({double lat, double lon}) _prefectureCentroid(String code) {
    final box = kJmaPrefectureBoundingBoxes[code]!;
    return (
      lat: (box.south + box.north) / 2,
      lon: (box.west + box.east) / 2,
    );
  }

  void _save() {
    final strings = widget.strings;
    if (_mode == _EntryMode.prefecture) {
      final code = _prefectureCode;
      if (code == null) {
        setState(() => _error = strings.placeEntryInvalidCoords);
        return;
      }
      final c = _prefectureCentroid(code);
      // The label defaults to the prefecture NAME (a PLACE), never a person.
      Navigator.pop(
        context,
        SavedPlace(lat: c.lat, lon: c.lon, label: strings.prefectureName(code)),
      );
      return;
    }

    // Coordinates mode: validate the typed lat/lon strictly.
    final lat = double.tryParse(_latCtl.text.trim());
    final lon = double.tryParse(_lonCtl.text.trim());
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      setState(() => _error = strings.placeEntryInvalidCoords);
      return;
    }
    Navigator.pop(
      context,
      SavedPlace(lat: lat, lon: lon, label: _labelCtl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(strings.placeEntryTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_EntryMode>(
              segments: [
                ButtonSegment<_EntryMode>(
                  value: _EntryMode.prefecture,
                  label: Text(strings.placeEntryModePrefecture),
                ),
                ButtonSegment<_EntryMode>(
                  value: _EntryMode.coordinates,
                  label: Text(strings.placeEntryModeCoordinates),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() {
                _mode = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            if (_mode == _EntryMode.prefecture) ...[
              DropdownButton<String>(
                isExpanded: true,
                value: _prefectureCode,
                hint: Text(strings.placeEntryPrefectureHint),
                items: [
                  for (final code in kJmaPrefectureBoundingBoxes.keys)
                    DropdownMenuItem<String>(
                      value: code,
                      child: Text(strings.prefectureName(code)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _prefectureCode = v;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              Text(
                strings.placeEntryCoarseNote,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              TextFormField(
                controller: _latCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(labelText: strings.placeEntryLatLabel),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _lonCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(labelText: strings.placeEntryLonLabel),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _labelCtl,
                decoration: InputDecoration(
                  labelText: strings.placeEntryLabelLabel,
                  hintText: strings.placeEntryLabelHint,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              strings.placeEntryLocalOnlyNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(strings.placeEntryCancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(strings.placeEntrySave),
        ),
      ],
    );
  }
}
