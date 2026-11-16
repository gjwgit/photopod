/// The frame People and Tags share: the Analyser's sections of the album.
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

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/analyser_section.dart';
import 'package:photopod/services/media_index.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/widgets/demo_banner.dart';

/// What a section of the album worked out by the Analyser looks like around
/// its own content: a status line, the button that reads the album again,
/// and the messages shown while there is nothing to list.
///
/// Opening the section sends nothing anywhere: it reads what is in the Pod
/// already and finishes a request cut short ([AnalyserSection.refresh]).
/// Photos are looked at only when the user asks, with Identify People or
/// Tag Photos, in the Library or in the section's Unprocessed row.
///
/// [T] is the section, read from the provider; [C] is what it shows.

class AnalyserSectionView<T extends AnalyserSection, C> extends StatefulWidget {
  const AnalyserSectionView({
    super.key,
    required this.keyPrompt,
    required this.lookingFor,
    required this.contentOf,
    required this.isEmpty,
    required this.summary,
    required this.errorTitle,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyText,
    required this.builder,
  });

  /// Why the security key is asked for.

  final String keyPrompt;

  /// What the Analyser looks for, as in "Looking for faces".

  final String lookingFor;

  /// What the section shows of the album's photos.

  final C Function(T section, List<MediaItem> photos) contentOf;

  /// Whether [C] has nothing to show at all.

  final bool Function(C content) isEmpty;

  /// The status line while nothing is under way.

  final String Function(T section, C content) summary;

  /// What is said when the section could not be read.

  final String errorTitle;

  /// What is said while there is nothing to show.

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyText;

  /// The list itself, given a way to read the album again, as after Get
  /// Info has changed a photo.

  final Widget Function(
    BuildContext context,
    T section,
    C content,
    VoidCallback refresh,
  )
  builder;

  @override
  State<AnalyserSectionView<T, C>> createState() =>
      _AnalyserSectionViewState<T, C>();
}

class _AnalyserSectionViewState<T extends AnalyserSection, C>
    extends State<AnalyserSectionView<T, C>> {
  String? _keyError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh({bool force = false}) async {
    final index = context.read<MediaIndex>();
    final section = context.read<T>();

    await index.refresh(force: force);
    if (!mounted) return;

    // The section's file and the catalog are both encrypted, so the
    // security key has to be in hand before either can be read. The samples
    // shown before login are neither.

    if (!index.isDemo) {
      if (!await _unlock()) return;
      if (!mounted) return;
    }

    await section.refresh(
      index.photos,
      prune: !index.isTruncated && index.error == null,
    );
  }

  // Ask for the security key if it is needed, returning whether it is now
  // in hand.

  Future<bool> _unlock() async {
    try {
      await getKeyFromUserIfRequired(context, Text(widget.keyPrompt));
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
    final section = context.watch<T>();
    final content = widget.contentOf(section, index.photos);

    return Column(
      children: [
        if (index.isDemo) const DemoBanner(),
        _buildStatusBar(context, index, section, content),
        const Divider(height: 1),
        Expanded(child: _buildBody(context, index, section, content)),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    MediaIndex index,
    T section,
    C content,
  ) {
    final busy = section.isScanning || index.isLoading;
    final summary =
        section.status ??
        (busy
            ? section.toDo > 0 && section.done < section.toDo
                  ? 'Leaving photos for the ${Analyser.displayName}...  '
                        '${section.done} of ${section.toDo}'
                  : 'Looking for ${widget.lookingFor}...'
            : '${widget.summary(section, content)}'
                  '${section.failed > 0 ? ' (${section.failed} unreadable)' : ''}');

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
    T section,
    C content,
  ) {
    final error = _keyError ?? section.error ?? index.error;
    final empty = widget.isEmpty(content);
    if (error != null && empty) {
      return analyserMessage(
        context,
        Icons.cloud_off,
        widget.errorTitle,
        error,
      );
    }
    if (empty) {
      return analyserMessage(
        context,
        widget.emptyIcon,
        widget.emptyTitle,
        widget.emptyText,
      );
    }
    return widget.builder(context, section, content, _refresh);
  }
}

/// Have the Analyser look at [photos], every photo not yet looked at, once
/// the user agrees to how many that is. [action] names the request, as on
/// its button ("Identify People"); [finding] says what it does ("find the
/// people in").

Future<void> askToAnalyse(
  BuildContext context,
  AnalyserSection section,
  List<MediaItem> photos, {
  required String action,
  required String finding,
}) async {
  final count = photos.length == 1 ? 'one photo' : '${photos.length} photos';
  final agreed = await showConfirmDialog(
    context,
    title: action,
    message:
        'Have the ${Analyser.displayName} $finding $count not yet looked at? '
        'They are sent without where they were taken, and the Analyser '
        'keeps no copy.',
    confirmLabel: action,
    destructive: false,
  );
  if (!agreed || !context.mounted) return;
  await section.analyse(photos);
}

/// A large icon, a title and a few words, in the middle of the section.

Widget analyserMessage(
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
