/// People through the Analyser: photos into the face inbox, answers back.
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

part of 'people.dart';

/// How often the inbox is looked at while photos are waiting in it. The
/// Analyser looks at it every ten seconds or so.

const Duration _lookEvery = Duration(seconds: 5);

/// How long the inbox may go without a single answer coming back before the
/// app stops waiting. The photos stay in the inbox, and the answers are
/// collected the next time People is opened.

const Duration _patience = Duration(minutes: 2);

/// How many photos are left in the inbox between looks for answers, so that
/// people start to appear while a long backlog is still being left.

const int _lookAfter = 20;

/// How long after a photo is added the inbox is first looked at, so that a
/// batch of photos is waited for once.

const Duration _addedDelay = Duration(seconds: 10);

extension _PeopleAnalyser on People {
  /// Leave every photo in [todo] not yet in the inbox there, then wait for
  /// the Analyser's answers.

  Future<void> _scanWithAnalyser(List<MediaItem> todo) async {
    if (!await FaceInbox.isEnabled()) {
      _needsConsent = true;
      return;
    }

    // Answers left from before, as for photos added on another device or
    // answered after the app closed, are filed first.

    _status = 'Collecting what the ${FaceAnalyser.displayName} found...';
    _changed();
    final listing = await _collect();

    final toSend = [
      for (final item in todo)
        if (!_book.hasScanned(item.path) &&
            !listing.waiting.contains(faceKeyOf(item.path)))
          item,
    ];
    _toDo = toSend.length;
    _status = null;
    _changed();

    for (final item in toSend) {
      if (_cancelled) return;
      try {
        final image =
            await MediaRenditions.readLarge(item) ?? await _renderLarge(item);
        if (image == null) throw StateError('no picture');
        await FaceInbox.leave(item.path, image);
      } on Object catch (e) {
        _failed++;
        debugPrint(
          'PhotoPod: could not leave ${item.url} for the Analyser: $e',
        );
      }
      _done++;
      _changed();
      if (_done % _lookAfter == 0) await _collect();
    }

    await _waitForAnswers();
  }

  /// A large rendition of [item] made from its original, for a photo with
  /// none stored: one added before renditions were kept, or a GIF, whose
  /// preview is its original. Never the original itself, which can be many
  /// megabytes and in a format [FaceInbox.leave] cannot clean.

  Future<Uint8List?> _renderLarge(MediaItem item) async {
    final original = await ThumbnailCache.instance.original(item);
    final made = await compute(renderPhoto, (
      bytes: original,
      keepOriginal: false,
    ));
    return made?.large;
  }

  /// Look at the inbox every few seconds while photos are waiting in it,
  /// until they have all been answered or none has been for a while.

  Future<void> _waitForAnswers() async {
    var lastAnswer = DateTime.now();
    while (!_cancelled) {
      final listing = await _collect();
      if (listing.waiting.isEmpty) break;
      if (listing.answered.isNotEmpty) lastAnswer = DateTime.now();
      if (DateTime.now().difference(lastAnswer) > _patience) {
        _status =
            '${listing.waiting.length} photos are waiting for the '
            '${FaceAnalyser.displayName}';
        _changed();
        return;
      }
      await Future<void>.delayed(_lookEvery);
    }
    _status = null;
  }

  /// File every answer in the inbox in the faces file, save it, and only
  /// then delete the answers, returning what the inbox held.

  Future<FaceInboxListing> _collect() async {
    final listing = await FaceInbox.list();
    _waiting = listing.waiting.length;
    _status = _waiting > 0
        ? 'The ${FaceAnalyser.displayName} has $_waiting '
              '${_waiting == 1 ? 'photo' : 'photos'} still to look at'
        : null;
    _changed();

    final filed = <String>[];
    final photos = <String>{};
    for (final key in listing.answered) {
      final path = _pathOf[key];
      try {
        final answer = await FaceInbox.readAnswer(key);
        if (path == null) {
          // A photo this session does not know of waits for a scan of
          // People, which knows every photo, unless the album is complete
          // and the photo is gone.
          if (_knowsAll) filed.add(key);
          continue;
        }
        if (answer != null && !_forgotten.contains(path)) {
          _book.addPhoto(path, answer.faces, url: _urlOf[path]);
          photos.add(path);
          if (answer.failed != null) _failed++;
        }
        filed.add(key);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not read the answer for $key: $e');
      }
    }

    if (filed.isEmpty) return listing;

    // A face found where the user has named someone in Get Info takes that
    // name, and the people named in these photos are listed in the catalog.

    photos.addAll(await _nameFromCatalog());
    await _save();
    await _toCatalog(photos);
    for (final key in filed) {
      try {
        await FaceInbox.deleteAnswer(key);
      } on Object catch (e) {
        debugPrint('PhotoPod: could not delete the answer for $key: $e');
      }
    }
    _changed();
    return listing;
  }

  // A photo has just been left in the inbox as it was added: wait for its
  // answer once the batch it came with is in.

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(_addedDelay, () => unawaited(_collectAdded()));
  }

  Future<void> _collectAdded() async {
    if (_scanning || _demo) return;
    _scanning = true;
    _changed();
    try {
      await load();
      await _waitForAnswers();
    } on Object catch (e) {
      debugPrint('PhotoPod: could not collect the faces of new photos: $e');
    } finally {
      _scanning = false;
      _changed();
    }
  }
}
