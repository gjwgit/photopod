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

import 'package:gap/gap.dart';
import 'package:provider/provider.dart';
import 'package:solidpod/solidpod.dart' show KeyManager;
import 'package:solidui/solidui.dart' show getKeyFromUserIfRequired;

import 'package:photopod/constants/face_analyser.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/dialogs/person_dialogs.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/services/media_index.dart';
import 'package:photopod/services/people.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/widgets/demo_banner.dart';
import 'package:photopod/widgets/person_section.dart';

/// The People section: the user's photos arranged by who is in them. First
/// everyone named, by the user or the Analyser, alphabetically, each above a
/// row of the photos they are in; then everyone the Analyser found and no
/// one has named, each as Unknown and a code of their own, most photos
/// first, so that naming one names them in all their photos; then the
/// photos the Analyser has not looked at.
///
/// Opening the section sends nothing anywhere. Photos are looked at only when
/// the user asks, with Identify People, in the Library or here.

class PeopleView extends StatefulWidget {
  const PeopleView({super.key});

  @override
  State<PeopleView> createState() => _PeopleViewState();
}

class _PeopleViewState extends State<PeopleView> {
  String? _keyError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final index = context.read<MediaIndex>();
    final people = context.read<People>();

    await index.refresh(force: force);
    if (!mounted) return;

    // The faces file and the catalog are both encrypted, so the security key
    // has to be in hand before either can be read. The samples shown before
    // login are neither.

    if (!index.isDemo) {
      if (!await _unlock()) return;
      if (!mounted) return;
    }

    await people.refresh(
      index.photos,
      prune: !index.isTruncated && index.error == null,
    );
  }

  // Ask for the security key if it is needed, returning whether it is now
  // in hand.

  Future<bool> _unlock() async {
    try {
      await getKeyFromUserIfRequired(
        context,
        const Text(
          'Please enter your security key to see the people in your photos',
        ),
      );
      if (!await KeyManager.hasSecurityKey()) {
        throw Exception('The security key is needed to read your photos.');
      }
      await PodKeys.prime();
    } on Object catch (e) {
      if (mounted) setState(() => _keyError = '$e');
      return false;
    }
    if (mounted) setState(() => _keyError = null);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final index = context.watch<MediaIndex>();
    final people = context.watch<People>();
    final sections = people.sectionsOf(index.photos);

    return Column(
      children: [
        if (index.isDemo) const DemoBanner(),
        _buildStatusBar(context, index, people, sections),
        const Divider(height: 1),
        Expanded(child: _buildBody(context, index, people, sections)),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    MediaIndex index,
    People people,
    PeopleSections sections,
  ) {
    final busy = people.isScanning || index.isLoading;
    final count = sections.named.length;
    final summary =
        people.status ??
        (busy
            ? people.toDo > 0 && people.done < people.toDo
                  ? 'Leaving photos for the ${FaceAnalyser.displayName}...  '
                        '${people.done} of ${people.toDo}'
                  : 'Looking for faces...'
            : '$count ${count == 1 ? 'person' : 'people'} named, '
                  '${sections.unknown.length} unknown, '
                  '${sections.unprocessed.length} not yet looked at'
                  '${people.failed > 0 ? ' (${people.failed} unreadable)' : ''}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Expanded(
            child: Text(summary, style: Theme.of(context).textTheme.bodySmall),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Read the album again',
            onPressed: busy ? null : () => _refresh(force: true),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MediaIndex index,
    People people,
    PeopleSections sections,
  ) {
    final error = _keyError ?? people.error ?? index.error;
    final empty =
        sections.named.isEmpty &&
        sections.unknown.isEmpty &&
        sections.unprocessed.isEmpty;
    if (error != null && empty) {
      return _message(context, Icons.cloud_off, 'Could not find people', error);
    }
    if (empty) {
      return _message(
        context,
        Icons.face_outlined,
        'No photos yet',
        'Add photos in the Library, then select some and tap Identify '
            'People to find who is in them.',
      );
    }

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
            onPreviewClosed: _refresh,
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
            onPreviewClosed: _refresh,
          ),
        if (sections.unprocessed.isNotEmpty)
          PersonSection(
            key: const ValueKey('unprocessed'),
            title: 'Unprocessed',
            icon: Icons.hourglass_empty,
            items: sections.unprocessed,
            tileExtent: extent,
            onPreviewClosed: _refresh,
            action: FilledButton.tonalIcon(
              icon: const Icon(Icons.face_outlined),
              label: const Text('Identify People'),
              onPressed: people.isScanning
                  ? null
                  : () => _identify(context, sections.unprocessed),
            ),
          ),
      ],
    );
  }

  // Have every photo not yet looked at looked at, once the user agrees to
  // how many that is.

  Future<void> _identify(BuildContext context, List<MediaItem> photos) async {
    final count = photos.length == 1 ? 'one photo' : '${photos.length} photos';
    final agreed = await showConfirmDialog(
      context,
      title: 'Identify People',
      message:
          'Have the ${FaceAnalyser.displayName} find the people in $count '
          'not yet looked at? They are sent without where they were taken, '
          'and the Analyser keeps no copy.',
      confirmLabel: 'Identify People',
      destructive: false,
    );
    if (!agreed || !context.mounted) return;
    await context.read<People>().analyse(photos);
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

  Widget _message(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const Gap(16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      ),
    ),
  );
}
