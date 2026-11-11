/// The frame People and Tags share: status line, consent and turning off.
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
/// its own content: a status line, the screen that turns the section on,
/// the button that turns it off, and the messages shown while there is
/// nothing to list.
///
/// Opening the section is what starts the scan, as opening Maps starts the
/// search for places. What is already in the Pod is read first, and only
/// the photos not looked at before are left in the section's inbox for the
/// Analyser. The scan carries on in the background if the user moves
/// elsewhere.
///
/// Nothing is shared until the user turns the section on here, which shares
/// its inbox, and only that, with the Analyser. [T] is the section, read
/// from the provider; [E] is what it lists.

class AnalyserSectionView<T extends AnalyserSection, E> extends StatefulWidget {
  const AnalyserSectionView({
    super.key,
    required this.name,
    required this.icon,
    required this.offIcon,
    required this.consentTitle,
    required this.consentText,
    required this.keyPrompt,
    required this.lookingFor,
    required this.entriesOf,
    required this.summary,
    required this.emptyText,
    required this.builder,
  });

  /// The section's name, as on its button: "People", "Tags".

  final String name;

  final IconData icon;

  /// The icon of the button that turns the section off.

  final IconData offIcon;

  /// What turning the section on offers, and what it means.

  final String consentTitle;
  final String consentText;

  /// Why the security key is asked for.

  final String keyPrompt;

  /// What the scan looks for, as in "Looking for faces".

  final String lookingFor;

  /// What the section lists among the album's photos.

  final List<E> Function(T section, List<MediaItem> photos) entriesOf;

  /// The status line once a scan is done, for [count] entries.

  final String Function(T section, int count) summary;

  /// What is said while nothing has been found.

  final String emptyText;

  /// The list itself, for entries that are there.

  final Widget Function(BuildContext context, T section, List<E> entries)
  builder;

  @override
  State<AnalyserSectionView<T, E>> createState() => _AnalyserSectionViewState();
}

class _AnalyserSectionViewState<T extends AnalyserSection, E>
    extends State<AnalyserSectionView<T, E>> {
  String? _keyError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan({bool force = false}) async {
    final index = context.read<MediaIndex>();
    final section = context.read<T>();

    await index.refresh(force: force);
    if (!mounted) return;

    // The section's file and the photos are both encrypted, so the security
    // key has to be in hand before either can be read. The samples shown
    // before login are neither.

    if (!index.isDemo) {
      if (!await _unlock()) return;
      if (!mounted) return;
    }

    await section.scan(
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
    final entries = widget.entriesOf(section, index.photos);

    return Column(
      children: [
        if (index.isDemo) const DemoBanner(),
        _buildStatusBar(context, index, section, entries.length),
        const Divider(height: 1),
        Expanded(child: _buildBody(context, index, section, entries)),
      ],
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    MediaIndex index,
    T section,
    int count,
  ) {
    final busy = section.isScanning || index.isLoading;
    final summary =
        section.status ??
        (busy
            ? section.toDo > 0 && section.done < section.toDo
                  ? 'Leaving photos for the ${Analyser.displayName}...  '
                        '${section.done} of ${section.toDo}'
                  : 'Looking for ${widget.lookingFor}...'
            : '${widget.summary(section, count)}'
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
            tooltip: 'Look for new photos again',
            onPressed: busy ? null : () => _scan(force: true),
          ),
          if (!index.isDemo && !section.needsConsent)
            IconButton(
              icon: Icon(widget.offIcon),
              tooltip:
                  'Turn ${widget.name} off and stop sharing with the '
                  '${Analyser.displayName}',
              onPressed: busy ? null : () => _disable(context),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    MediaIndex index,
    T section,
    List<E> entries,
  ) {
    if (section.needsConsent && !index.isDemo) return _consent(context);

    final error = _keyError ?? section.error ?? index.error;
    if (error != null && entries.isEmpty) {
      return analyserMessage(
        context,
        Icons.cloud_off,
        'Could not look for ${widget.lookingFor}',
        error,
      );
    }

    if (entries.isEmpty) {
      return analyserMessage(
        context,
        widget.icon,
        section.isScanning
            ? 'Looking for ${widget.lookingFor}'
            : 'No ${widget.name.toLowerCase()} yet',
        section.isScanning
            ? '${widget.name} appear here as the ${Analyser.displayName} '
                  'finds them.'
            : widget.emptyText,
      );
    }

    return widget.builder(context, section, entries);
  }

  // What turning the section on means, and the button that does it.

  Widget _consent(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const Gap(16),
            Text(
              widget.consentTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Gap(8),
            Text(widget.consentText, textAlign: TextAlign.center),
            const Gap(24),
            FilledButton.icon(
              icon: Icon(widget.icon),
              label: Text('Turn on ${widget.name}'),
              onPressed: () => _enable(context),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _enable(BuildContext context) async {
    try {
      await context.read<T>().enable();
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(
          context,
          'Could not turn ${widget.name} on',
          '$e',
        );
      }
      return;
    }
    if (mounted) await _scan();
  }

  Future<void> _disable(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Turn ${widget.name} off?',
      message:
          'Your photos will no longer be shared with the '
          '${Analyser.displayName} for ${widget.name}, and any still waiting '
          'are removed. What has been found already stays.',
      confirmLabel: 'Turn off',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await context.read<T>().disable();
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(
          context,
          'Could not turn ${widget.name} off',
          '$e',
        );
      }
    }
  }
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
