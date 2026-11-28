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
import 'package:photopod/dialogs/analyser_choice_dialog.dart';
import 'package:photopod/dialogs/message_dialog.dart';
import 'package:photopod/models/analyser_choice.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/services/analyser_section.dart';
import 'package:photopod/services/media_index.dart';
import 'package:photopod/services/pod_keys.dart';

/// What a section of the album worked out by the Analyser looks like around
/// its own content: a status line, the buttons that choose the analyser and
/// read the album again, and the messages shown while there is nothing to
/// list.
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
    required this.deleteLabel,
    required this.deleteMessage,
    this.selected = const [],
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

  /// What the button that deletes what the analysers found is called, on
  /// its tooltip and over the question it asks first.

  final String deleteLabel;

  /// The question the button asks first: given null, about deleting what
  /// was found in every photo; given words such as "the 3 selected photos",
  /// about deleting what was found in those.

  final String Function(String? photos) deleteMessage;

  /// The photos selected in the browser. With none, the delete button
  /// deletes what was found in every photo; with some, only what was found
  /// in them.

  final List<MediaItem> selected;

  /// The list itself. The browser the section sits in brings it up to date
  /// once Get Info, from the preview or on its own, may have changed a photo.

  final Widget Function(BuildContext context, T section, C content) builder;

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
    final chosen = context.watch<AnalyserChoice>().chosen;
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
            icon: Icon(
              chosen == AnalyserBackend.teePod
                  ? Icons.verified_user_outlined
                  : Icons.shield_outlined,
            ),
            tooltip: chosen == null
                ? 'Choose the analyser'
                : 'Analyser: ${chosen.label} (${chosen.privacy.toLowerCase()}). '
                      'Tap to change it.',
            onPressed: section.isScanning
                ? null
                : () => showAnalyserChoiceDialog(context),
          ),
          _buildDeleteButton(section, busy),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Read the album again',
            onPressed: busy ? null : () => _refresh(force: true),
          ),
        ],
      ),
    );
  }

  // The button that deletes what the analysers found: in the selected
  // photos when there are any, and otherwise in every photo.

  Widget _buildDeleteButton(T section, bool busy) {
    final String tooltip;
    final VoidCallback? onPressed;
    if (widget.selected.isEmpty) {
      tooltip = '${widget.deleteLabel} of All Photos';
      onPressed = busy || section.scannedCount == 0
          ? null
          : () => _deleteResults(section, null);
    } else {
      final photos = [
        for (final item in widget.selected)
          if (item.isPhoto &&
              !item.isShared &&
              section.hasResultsFor(item.path))
            item,
      ];
      tooltip = photos.isEmpty
          ? 'None of the selected photos has any ${widget.lookingFor} found '
                'in it to delete'
          : '${widget.deleteLabel} of the ${_selectedPhrase(photos.length)}';
      onPressed = busy || photos.isEmpty
          ? null
          : () => _deleteResults(section, photos);
    }
    return IconButton(
      icon: const Icon(Icons.delete_sweep_outlined),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  static String _selectedPhrase(int count) =>
      count == 1 ? 'Selected Photo' : '$count Selected Photos';

  // Ask before deleting what the analysers found in [photos], or in every
  // photo when [photos] is null, then say how it went.

  Future<void> _deleteResults(T section, List<MediaItem>? photos) async {
    final count = photos?.length;
    final agreed = await showConfirmDialog(
      context,
      title: count == null
          ? '${widget.deleteLabel} of All Photos'
          : '${widget.deleteLabel} of the ${_selectedPhrase(count)}',
      message: widget.deleteMessage(
        count == null
            ? null
            : count == 1
            ? 'the selected photo'
            : 'the $count selected photos',
      ),
    );
    if (!agreed || !mounted) return;
    final deleted = await section.deleteResults(photos);
    if (!deleted || !mounted) return;
    final what = widget.lookingFor;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          count == null
              ? 'Deleted all the $what found.'
              : 'Deleted the $what found in '
                    '${count == 1 ? 'the selected photo' : '$count selected photos'}.',
        ),
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
    return widget.builder(context, section, content);
  }
}

/// Have the analyser the user chose look at [photos], every photo not yet
/// looked at, once the user agrees to how many that is. The user is asked
/// to choose an analyser first if they have not. [action] names the
/// request, as on its button ("Identify People"); [finding] says what it
/// does ("find the people in").

Future<void> askToAnalyse(
  BuildContext context,
  AnalyserSection section,
  List<MediaItem> photos, {
  required String action,
  required String finding,
}) async {
  final backend = await chosenAnalyser(context);
  if (backend == null || !context.mounted) return;
  final count = photos.length == 1 ? 'one photo' : '${photos.length} photos';
  final how = switch (backend) {
    AnalyserBackend.teePod =>
      'They go straight to ${backend.label}, in a trusted execution '
          'environment, once it has proved what it is.',
    AnalyserBackend.solidCommunity =>
      'They are shared, encrypted, with the ${Analyser.displayName} on the '
          'Solid Community server until it has answered.',
  };
  final agreed = await showConfirmDialog(
    context,
    title: action,
    message:
        'Have ${backend.label} $finding $count not yet looked at? $how '
        'They are sent without where they were taken, and the analyser '
        'keeps no copy.\n\n'
        '${backend.privacy}. To use the other analyser, tap the shield '
        'icon above the photos.',
    confirmLabel: action,
    destructive: false,
  );
  if (!agreed || !context.mounted) return;
  await section.analyse(photos, backend: backend);
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
