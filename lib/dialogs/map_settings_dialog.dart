/// Choose which map provider the map is drawn from.
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

import 'package:photopod/models/map_source.dart';

/// Let the user pick a map provider, after GeoPod's Map Settings.
///
/// [onChanged] is called as soon as a provider is picked, so the map behind
/// the dialogue redraws straight away and the user can see what they chose.

Future<void> showMapSettingsDialog(
  BuildContext context, {
  required MapSource current,
  required ValueChanged<MapSource> onChanged,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _MapSettingsDialog(current: current, onChanged: onChanged),
);

class _MapSettingsDialog extends StatefulWidget {
  const _MapSettingsDialog({required this.current, required this.onChanged});

  final MapSource current;
  final ValueChanged<MapSource> onChanged;

  @override
  State<_MapSettingsDialog> createState() => _MapSettingsDialogState();
}

class _MapSettingsDialogState extends State<_MapSettingsDialog> {
  late MapSource _source = widget.current;

  void _pick(MapSource? source) {
    if (source == null || source == _source) return;
    setState(() => _source = source);
    widget.onChanged(source);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Map Settings'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Map provider', style: theme.textTheme.labelLarge),
            const Gap(8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<MapSource>(
                value: _source,
                isExpanded: true,
                itemHeight: 56,
                underline: const SizedBox(),
                items: [
                  for (final source in MapSource.values)
                    DropdownMenuItem(
                      value: source,
                      child: Row(
                        children: [
                          Icon(source.icon, size: 20, color: scheme.outline),
                          const Gap(12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  source.label,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  source.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: _pick,
              ),
            ),
            const Gap(12),
            Text(
              'The choice is kept on this device. Map tiles are fetched '
              'straight from the provider, which therefore sees the areas '
              'being viewed, but your photos are never sent to it.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
