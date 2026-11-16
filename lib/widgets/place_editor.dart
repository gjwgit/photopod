/// Where a photo was taken: shown, typed in and looked up.
///
/// Copyright (C) 2026, Togaware Pty Ltd.
///
/// Licensed under the GNU General Public License, Version 3 (the "License").
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Graham Williams

library;

import 'package:flutter/material.dart';

import 'package:gap/gap.dart';

import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/services/geocoder.dart';

/// Looks up the places a name could mean; see [geocode].

typedef PlaceLookup = Future<List<PhotoPlace>> Function(String text);

/// The place a photo was taken, with a field to type another.
///
/// What is typed is looked up when the user presses Enter or the search
/// button, never while they type, and the places found are offered to choose
/// from, since a name such as `Richmond` means many places. Coordinates
/// typed as `latitude, longitude` are taken as they stand.

class PlaceEditor extends StatefulWidget {
  const PlaceEditor({
    super.key,
    required this.place,
    required this.onChanged,
    this.photoLocation,
    this.lookup = _geocode,
  });

  /// The place the user gave, if any.

  final PhotoPlace? place;

  /// Where the photo itself says it was taken, if it does, which the place
  /// the user gives stands in for.

  final String? photoLocation;

  /// Called with the place chosen, or null when it is taken away.

  final ValueChanged<PhotoPlace?> onChanged;

  final PlaceLookup lookup;

  static Future<List<PhotoPlace>> _geocode(String text) => geocode(text);

  @override
  State<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<PlaceEditor> {
  final TextEditingController _field = TextEditingController();
  List<PhotoPlace> _found = const [];
  bool _searching = false;
  String? _problem;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _field.text.trim();
    if (text.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _problem = null;
      _found = const [];
    });
    try {
      final found = await widget.lookup(text);
      if (!mounted) return;

      // Coordinates need no choosing between.

      if (found.length == 1 && placeFromCoordinates(text) != null) {
        _choose(found.single);
        return;
      }
      setState(() {
        _found = found;
        if (found.isEmpty) _problem = 'No place called "$text" was found';
      });
    } on Object catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _choose(PhotoPlace place) {
    setState(() {
      _found = const [];
      _problem = null;
      _field.clear();
    });
    widget.onChanged(place);
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final small = Theme.of(context).textTheme.bodySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (place != null)
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 20),
              const Gap(8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(place.name),
                    Text(_coordinates(place), style: small),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Forget this place',
                onPressed: () => widget.onChanged(null),
              ),
            ],
          )
        else if (widget.photoLocation != null)
          Text(
            'The photo says it was taken at ${widget.photoLocation}. A place '
            'given here is used in its stead.',
            style: small,
          ),
        const Gap(8),
        TextField(
          controller: _field,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.add_location_alt_outlined),
            hintText: place == null ? 'Add a place' : 'Change the place',
            helperText:
                'A place name, looked up with $geocoderName, or latitude, '
                'longitude',
            errorText: _problem,
            errorMaxLines: 3,
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Look up this place',
                    onPressed: _search,
                  ),
          ),
        ),
        for (final found in _found)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(found.name),
            subtitle: Text(_coordinates(found)),
            onTap: () => _choose(found),
          ),
      ],
    );
  }

  static String _coordinates(PhotoPlace place) =>
      '${place.latitude.toStringAsFixed(5)}, '
      '${place.longitude.toStringAsFixed(5)}';
}
