/// Let the user choose which analyser finds the faces and tags in photos.
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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:gap/gap.dart';
import 'package:provider/provider.dart';

import 'package:photopod/constants/analyser.dart';
import 'package:photopod/constants/teepod.dart';
import 'package:photopod/models/analyser_choice.dart';

/// The analyser to send photos to: the one chosen on this device, or, when
/// none has been, or TeePod was chosen and this build cannot reach it, the
/// one the user chooses now. Null when the user cancels.

Future<AnalyserBackend?> chosenAnalyser(BuildContext context) async {
  final choice = context.read<AnalyserChoice>();
  await choice.load();
  final chosen = choice.chosen;
  if (chosen == AnalyserBackend.solidCommunity) return chosen;
  if (chosen == AnalyserBackend.teePod &&
      await AnalyserChoice.teePodAvailable()) {
    return chosen;
  }
  if (!context.mounted) return null;
  return showAnalyserChoiceDialog(context);
}

/// Ask the user which analyser to use, saying how private each keeps the
/// photos, and remember the answer. Returns the analyser chosen, or null
/// when the user cancels, which leaves the earlier choice as it was.

Future<AnalyserBackend?> showAnalyserChoiceDialog(BuildContext context) async {
  final choice = context.read<AnalyserChoice>();
  await choice.load();
  if (!context.mounted) return null;
  final picked = await showDialog<AnalyserBackend>(
    context: context,
    builder: (context) => _AnalyserChoiceDialog(current: choice.chosen),
  );
  if (picked != null) await choice.choose(picked);
  return picked;
}

/// What the dialogue needs to know before it can offer the choice.

typedef _Facts = ({bool teePod, bool teePodDebug, String podHost});

Future<_Facts> _facts() async {
  final teePod = await AnalyserChoice.teePodAvailable();
  final config = teePod ? await TeePodConfig.load() : null;
  var podHost = 'the Solid Community server';
  try {
    podHost = Uri.parse(await Analyser.webId()).host;
  } on Object {
    // The generic name will do.
  }
  return (
    teePod: teePod,
    teePodDebug: config?.allowDebugImage ?? false,
    podHost: podHost,
  );
}

class _AnalyserChoiceDialog extends StatefulWidget {
  const _AnalyserChoiceDialog({required this.current});

  final AnalyserBackend? current;

  @override
  State<_AnalyserChoiceDialog> createState() => _AnalyserChoiceDialogState();
}

class _AnalyserChoiceDialogState extends State<_AnalyserChoiceDialog> {
  late final Future<_Facts> _known = _facts();
  AnalyserBackend? _picked;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose an analyser'),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<_Facts>(
          future: _known,
          builder: (context, snapshot) {
            final facts = snapshot.data;
            if (facts == null) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final picked = _picked ?? _initial(facts);

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Identify People and Tag Photos send the photos you '
                    'select to an analyser. Both analysers find the same '
                    'faces and tags; they differ in how private your '
                    'photos stay while they are looked at.',
                  ),
                  const Gap(12),
                  RadioGroup<AnalyserBackend>(
                    groupValue: picked,
                    onChanged: (value) => setState(() => _picked = value),
                    child: Column(
                      children: [
                        _option(
                          context,
                          AnalyserBackend.teePod,
                          enabled: facts.teePod,
                          details: _teePodDetails(facts),
                        ),
                        _option(
                          context,
                          AnalyserBackend.solidCommunity,
                          details:
                              'Your photos are left, encrypted, in a folder '
                              'of your Pod that is shared with the PhotoPod '
                              'Analyser on ${facts.podHost} until it has '
                              'answered. The Analyser runs on an ordinary '
                              'server, so whoever operates that server could '
                              'see your photos while they are being looked '
                              'at. It keeps no copy.',
                        ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  Text(
                    'Either way, photos are sent without where they were '
                    'taken, and what is found is saved, encrypted, in your '
                    'own Pod. You can change the analyser at any time from '
                    'People or Tags.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FutureBuilder<_Facts>(
          future: _known,
          builder: (context, snapshot) {
            final facts = snapshot.data;
            return FilledButton(
              onPressed: facts == null
                  ? null
                  : () => Navigator.of(context).pop(_picked ?? _initial(facts)),
              child: const Text('Use this analyser'),
            );
          },
        ),
      ],
    );
  }

  // What is offered before the user picks: what was chosen before, where it
  // can still be used, and otherwise the more private analyser wherever it
  // can be.

  AnalyserBackend _initial(_Facts facts) {
    final current = widget.current;
    if (current != null &&
        (current != AnalyserBackend.teePod || facts.teePod)) {
      return current;
    }
    return facts.teePod
        ? AnalyserBackend.teePod
        : AnalyserBackend.solidCommunity;
  }

  String _teePodDetails(_Facts facts) {
    if (!facts.teePod) {
      return kIsWeb
          ? 'Not available in the web version: a browser cannot make the '
                'verified connection TeePod requires. Use the desktop or '
                'Android app to choose TeePod.'
          : 'Not available in this build, which does not carry TeePod\'s '
                'client certificate.';
    }
    return 'Your photos go straight from this device to TeePod, which runs '
        'in a trusted execution environment (Google Cloud Confidential '
        'Space) whose memory even the server\'s operator cannot read. Before '
        'any photo is sent, PhotoPod checks Google\'s signed proof that '
        'TeePod is running the expected software. Nothing is shared from '
        'your Pod.'
        '${facts.teePodDebug ? ' TeePod is currently a test deployment, '
                  'whose operator can still look inside; this will '
                  'change once it is in production.' : ''}';
  }

  Widget _option(
    BuildContext context,
    AnalyserBackend backend, {
    required String details,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final higher = backend == AnalyserBackend.teePod;
    final badgeColour = higher
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;

    return RadioListTile<AnalyserBackend>(
      value: backend,
      enabled: enabled,
      contentPadding: EdgeInsets.zero,
      isThreeLine: true,
      title: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(backend.label),
          Chip(
            avatar: Icon(
              higher ? Icons.verified_user_outlined : Icons.shield_outlined,
              size: 16,
              color: enabled ? badgeColour : theme.disabledColor,
            ),
            label: Text(backend.privacy),
            labelStyle: theme.textTheme.labelSmall?.copyWith(
              color: enabled ? badgeColour : theme.disabledColor,
            ),
            side: BorderSide(
              color: enabled ? badgeColour : theme.disabledColor,
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(details),
      ),
    );
  }
}
