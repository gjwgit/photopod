/// The people in the album, each with the photos they are in.
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
/// Authors: Tony Chen

library;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/dialogs/person_dialogs.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/screens/analyser_section_view.dart';
import 'package:photopod/services/people.dart';
import 'package:photopod/widgets/person_section.dart';

/// The People section: everyone whose face turns up in the album, those in
/// the most photos first, each above a row of the photos they are in.
///
/// Nothing is shared until the user turns People on here, which shares the
/// face inbox, and only that, with the Analyser; Tags has an inbox of its
/// own, turned on apart. See [AnalyserSectionView].

class PeopleView extends StatelessWidget {
  const PeopleView({super.key});

  @override
  Widget build(BuildContext context) =>
      AnalyserSectionView<People, PersonEntry>(
        name: 'People',
        icon: Icons.face_outlined,
        offIcon: Icons.face_retouching_off,
        consentTitle: 'Find the people in your photos',
        consentText:
            'Faces are found by the ${Analyser.displayName}. Only one '
            'folder of your Pod is shared with it, and every photo in it '
            'stays encrypted. The Analyser opens a photo only to find the '
            'faces in it, keeps no copy, and returns what it found to your '
            'Pod, encrypted. Nothing else in your Pod is shared, and you '
            'can turn People off at any time, which ends the share.',
        keyPrompt:
            'Please enter your security key to find the people in your photos',
        lookingFor: 'faces',
        entriesOf: (people, photos) => people.peopleIn(photos),
        summary: (people, count) => count == 0
            ? 'No people found yet'
            : '$count ${count == 1 ? 'person' : 'people'} in '
                  '${people.scannedCount} photos looked at',
        emptyText:
            'Someone is listed once they are in at least '
            '$minPhotosPerPerson of your photos.',
        builder: (context, people, entries) {
          final extent = context.watch<ViewPrefs>().tileSize.extent;
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final entry in entries)
                PersonSection(
                  key: ValueKey(entry.id),
                  person: entry,
                  tileExtent: extent,
                  onRename: () => _rename(context, entry),
                  onMerge: entries.length < 2
                      ? null
                      : () => _merge(context, entry, entries),
                ),
            ],
          );
        },
      );

  Future<void> _rename(BuildContext context, PersonEntry entry) async {
    final name = await showPersonNameDialog(context, entry);
    if (name == null || !context.mounted) return;
    await context.read<People>().rename(entry.id, name);
  }

  // Two groups that are really one person, as happens when someone's looks
  // change over the years, are put together by hand.

  Future<void> _merge(
    BuildContext context,
    PersonEntry entry,
    List<PersonEntry> entries,
  ) async {
    final others = entries.where((other) => other.id != entry.id).toList();
    final target = await showMergePersonDialog(context, entry, others);
    if (target == null || !context.mounted) return;
    await context.read<People>().merge(entry.id, target.id);
  }
}
