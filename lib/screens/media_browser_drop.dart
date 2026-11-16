/// Dropping files from the desktop onto the Library.
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

part of 'media_browser.dart';

/// The drop target that takes photos and videos dragged from the desktop.

extension MediaBrowserDrop on MediaBrowserState {
  // Only the Library shows everything, so it alone takes files dragged from
  // the desktop, once it knows where the album is. While a drag hovers the
  // content is outlined and says where the files will go, so the drop is not
  // a leap of faith.

  Widget _buildDropTarget(BuildContext context, Widget child) {
    final enabled =
        widget.section == LibrarySection.library && _root.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return DropTarget(
      enable: enabled,
      onDragEntered: (_) => updateState(() => _dragging = true),
      onDragExited: (_) => updateState(() => _dragging = false),
      onDragDone: (details) {
        updateState(() => _dragging = false);
        _dropFiles(context, details.files);
      },
      child: Stack(
        children: [
          Positioned.fill(child: child),
          if (enabled && _dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.85),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_upload_outlined,
                          size: 56,
                          color: scheme.onPrimaryContainer,
                        ),
                        const Gap(12),
                        Text(
                          'Drop photos and videos to add them to your album',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
