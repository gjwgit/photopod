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

import 'package:photopod/dialogs/person_dialogs.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/screens/analyser_section_view.dart';
import 'package:photopod/services/people.dart';
import 'package:photopod/widgets/person_section.dart';

/// The People section: the user's photos arranged by who is in them. First
/// everyone named, by the user or the Analyser, alphabetically, each above a
/// row of the photos they are in; then everyone the Analyser found and no
/// one has named, each as Unknown and a code of their own, most photos
/// first, so that naming one names them in all their photos; then the
/// photos the Analyser has not looked at.
///
/// Opening the section sends nothing anywhere. Photos are looked at only when
/// the user asks, with Identify People, in the Library or here. See
/// [AnalyserSectionView].

class PeopleView extends StatelessWidget {
  const PeopleView({super.key});

  @override
  Widget build(BuildContext context) =>
      AnalyserSectionView<People, PeopleSections>(
        keyPrompt:
            'Please enter your security key to see the people in your photos',
        lookingFor: 'faces',
        contentOf: (people, photos) => people.sectionsOf(photos),
        isEmpty: (sections) =>
            sections.named.isEmpty &&
            sections.unknown.isEmpty &&
            sections.unprocessed.isEmpty,
        summary: (people, sections) {
          final count = sections.named.length;
          return '$count ${count == 1 ? 'person' : 'people'} named, '
              '${sections.unknown.length} unknown, '
              '${sections.unprocessed.length} not yet looked at';
        },
        errorTitle: 'Could not find people',
        emptyIcon: Icons.face_outlined,
        emptyTitle: 'No photos yet',
        emptyText:
            'Add photos in the Library, then select some and tap Identify '
            'People to find who is in them.',
        builder: _buildList,
      );

  Widget _buildList(
    BuildContext context,
    People people,
    PeopleSections sections,
    VoidCallback refresh,
  ) {
    final extent = context.watch<ViewPrefs>().tileSize.extent;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final entry in sections.named)
          PersonSection(
            key: ValueKey('person:${entry.id}'),
            title: entry.title,
            person: entry,
            items: entry.items,
            tileExtent: extent,
            onRename: () => _rename(context, entry),
            onPreviewClosed: refresh,
          ),
        for (final entry in sections.unknown)
          PersonSection(
            key: ValueKey(entry.id),
            title: entry.title,
            person: entry,
            unnamed: true,
            items: entry.items,
            tileExtent: extent,
            onRename: () => _rename(context, entry),
            onPreviewClosed: refresh,
          ),
        if (sections.unprocessed.isNotEmpty)
          PersonSection(
            key: const ValueKey('unprocessed'),
            title: 'Unprocessed',
            icon: Icons.hourglass_empty,
            items: sections.unprocessed,
            tileExtent: extent,
            onPreviewClosed: refresh,
            action: FilledButton.tonalIcon(
              icon: const Icon(Icons.face_outlined),
              label: const Text('Identify People'),
              onPressed: people.isScanning
                  ? null
                  : () => askToAnalyse(
                      context,
                      people,
                      sections.unprocessed,
                      action: 'Identify People',
                      finding: 'find the people in',
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _rename(BuildContext context, PersonEntry entry) async {
    final name = await showPersonNameDialog(context, entry);
    if (name == null || !context.mounted) return;
    final people = context.read<People>();
    final person = entry.person;
    if (person != null) {
      await people.namePerson(person, name);
    } else {
      await people.renamePerson(entry.title, name);
    }
  }
}
