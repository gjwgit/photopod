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

import 'package:photopod/dialogs/person_dialogs.dart';
import 'package:photopod/models/view_prefs.dart';
import 'package:photopod/services/media_index.dart';
import 'package:photopod/services/people.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/widgets/demo_banner.dart';
import 'package:photopod/widgets/person_section.dart';

/// The People section: everyone whose face turns up in the album, those in
/// the most photos first, each above a row of the photos they are in.
///
/// Opening the section is what starts the search for faces, as opening Maps
/// starts the search for places. Only photos not looked at before are read,
/// and the scan carries on in the background if the user moves elsewhere.

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan({bool force = false}) async {
    final index = context.read<MediaIndex>();
    final people = context.read<People>();
    if (!people.isSupported) return;

    await index.refresh(force: force);
    if (!mounted) return;

    // The faces file and the photos are both encrypted, so the security key
    // has to be in hand before either can be read. The samples shown before
    // login are neither.

    if (!index.isDemo) {
      if (!await _unlock()) return;
      if (!mounted) return;
    }

    await people.scan(
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
          'Please enter your security key to find the people in '
          'your photos',
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
    final entries = people.peopleIn(index.photos);

    return Column(
      children: [
        if (index.isDemo) const DemoBanner(),
        _buildStatusBar(context, index, people, entries.length),
        const Divider(height: 1),
        Expanded(child: _buildBody(context, index, people, entries)),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    MediaIndex index,
    People people,
    int count,
  ) {
    final busy = people.isScanning || index.isLoading;
    final summary =
        people.status ??
        (busy
            ? 'Looking for faces...  ${people.done} of ${people.toDo}'
            : count == 0
            ? 'No people found yet'
            : '$count ${count == 1 ? 'person' : 'people'} in '
                  '${people.scannedCount} photos looked at'
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
            tooltip: 'Look for new photos again',
            onPressed: busy || !people.isSupported
                ? null
                : () => _scan(force: true),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MediaIndex index,
    People people,
    List<PersonEntry> entries,
  ) {
    if (!people.isSupported) {
      return _message(
        context,
        Icons.face_retouching_off,
        'Not available here',
        'Recognising faces runs on your own device, using OpenCV, which the '
            'web version of PhotoPod cannot use. Open PhotoPod on your '
            'desktop, phone or tablet to see the people in your photos.',
      );
    }

    final error = _keyError ?? people.error ?? index.error;
    if (error != null && entries.isEmpty) {
      return _message(context, Icons.cloud_off, 'Could not find people', error);
    }

    if (entries.isEmpty) {
      return _message(
        context,
        Icons.face_outlined,
        people.isScanning ? 'Looking for faces' : 'No people yet',
        people.isScanning
            ? 'People appear here as their faces are found. Your photos are '
                  'looked at on this device, and only what describes each '
                  'face is kept, encrypted, in your Pod.'
            : 'Someone is listed once they are in at least '
                  '$minPhotosPerPerson of your photos.',
      );
    }

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
  }

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
