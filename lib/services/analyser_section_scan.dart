/// How a section asks the Analyser about photos and files the answers.
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

part of 'analyser_section.dart';

/// How often PhotoPod looks in its own inbox for answers while a request is
/// under way. The Analyser is told of the request by the server, and does
/// not look on a timer itself.

const Duration _lookEvery = Duration(seconds: 3);

/// How long a request may go without a single photo being answered before
/// it is given up: the share ends, and the photos still waiting are taken
/// out. They were never looked at, so they stay under Unprocessed.

const Duration _patience = Duration(minutes: 2);

extension _Scan on AnalyserSection {
  /// Ask the Analyser about every photo queued, a request at a time: leave
  /// them in the inbox, share it with the Analyser, file the answers as they
  /// come, and once it is done, end the share and remove the inbox. Photos
  /// chosen meanwhile make the next request.

  Future<void> _runAnalyser() async {
    while (_queue.isNotEmpty && !_cancelled) {
      await inbox.prepare();
      try {
        await _leaveQueued();
        if (_cancelled) break;
        _status = 'Asking the ${Analyser.displayName}...';
        _changed();
        await inbox.request();
        await _waitUntilDone();
      } finally {
        await _close();
      }
    }
  }

  /// Finish a request cut short, as by the app being closed: file whatever
  /// was answered, and close the inbox. Photos it had not answered are not
  /// waited for, and stay under Unprocessed.

  Future<void> _finishEarlier() async {
    try {
      final listing = await _collect();
      final count = listing.waiting.length;
      if (count > 0) {
        _status =
            '$count ${count == 1 ? 'photo was' : 'photos were'} not '
            'looked at last time, and ${count == 1 ? 'stays' : 'stay'} '
            'under Unprocessed.';
      }
    } finally {
      await _close();
    }
  }

  /// Leave each photo queued in the inbox, without where it was taken.

  Future<void> _leaveQueued() async {
    while (_queue.isNotEmpty && !_cancelled) {
      final item = _queue.removeAt(0);
      try {
        final image =
            await MediaRenditions.readLarge(item) ?? await _renderLarge(item);
        if (image == null) throw StateError('no picture');
        await inbox.leave(item.path, image);
      } on Object catch (e) {
        _failed++;
        debugPrint(
          'PhotoPod: could not leave ${item.url} for the Analyser: $e',
        );
      }
      _done++;
      _changed();
    }
  }

  /// A large rendition of [item] made from its original, for a photo with
  /// none stored: one added before renditions were kept, or a GIF, whose
  /// preview is its original. Never the original itself, which can be many
  /// megabytes and in a format [AnalyserInbox.leave] cannot clean.

  Future<Uint8List?> _renderLarge(MediaItem item) async {
    final original = await ThumbnailCache.instance.original(item);
    final made = await compute(renderPhoto, (
      bytes: original,
      keepOriginal: false,
    ));
    return made?.large;
  }

  /// File the answers as they come, until the Analyser says it is done, or
  /// has answered nothing for a while.

  Future<void> _waitUntilDone() async {
    var lastProgress = DateTime.now();
    var waiting = -1;
    while (!_cancelled) {
      await Future<void>.delayed(_lookEvery);
      final listing = await _collect();
      if (listing.done) {
        _status = null;
        return;
      }
      if (listing.answered.isNotEmpty || listing.waiting.length != waiting) {
        lastProgress = DateTime.now();
        waiting = listing.waiting.length;
      }
      if (DateTime.now().difference(lastProgress) > _patience) {
        final count = listing.waiting.length;
        _status =
            'The ${Analyser.displayName} did not answer, so $count '
            '${count == 1 ? 'photo was' : 'photos were'} not looked at, and '
            '${count == 1 ? 'stays' : 'stay'} under Unprocessed.';
        return;
      }
    }
  }

  // End the share and remove the inbox, whatever happened.

  Future<void> _close() async {
    try {
      await inbox.close();
    } on Object catch (e) {
      // Left there, it is closed the next time the section is opened.
      debugPrint('PhotoPod: could not close the ${inbox.label}: $e');
    }
    _waiting = 0;
  }

  /// File every answer in the inbox, save the file, and only then delete
  /// the answers, returning what the inbox held. An answer for a photo not
  /// known here, as from a request made on another device, is left, and
  /// goes when the inbox is closed.

  Future<InboxListing> _collect() async {
    final listing = await inbox.list();
    _waiting = listing.waiting.length;
    if (!listing.done) {
      _status = _waiting > 0
          ? 'The ${Analyser.displayName} has $_waiting '
                '${_waiting == 1 ? 'photo' : 'photos'} still to look at'
          : null;
    }
    _changed();

    final filed = <String>[];
    final photos = <String>{};
    for (final key in listing.answered) {
      final path = _pathOf[key];
      if (path == null) continue;
      try {
        final answer = await inbox.readAnswer(key);
        if (!_forgotten.contains(path)) {
          if (fileAnswer(path, answer, url: _urlOf[path])) _failed++;
          photos.add(path);
        }
        filed.add(key);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not read the answer for $key: $e');
      }
    }

    if (filed.isEmpty) return listing;

    // What the user has said in Get Info is taken on, and what was found in
    // these photos is told to the catalog.

    photos.addAll(await fromCatalog());
    await save();
    await toCatalog(photos);
    for (final key in filed) {
      try {
        await inbox.deleteAnswer(key);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not delete the answer for $key: $e');
      }
    }
    _changed();
    return listing;
  }
}
