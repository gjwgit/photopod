/// People through the Analyser: the face inbox out, the results back.
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

/// How many photos are left in the inbox between asking the Analyser to
/// look, so that people start to appear while a long backlog is still being
/// sent.

const int _askEvery = 20;

/// The most runs one scan asks for, a guard against a run that keeps
/// reporting work it never finishes.

const int _maxRuns = 200;

/// How long after a photo is added the Analyser is asked to look, so that
/// adding a batch of photos asks once rather than once a photo.

const Duration _addedDelay = Duration(seconds: 5);

extension _PeopleAnalyser on People {
  /// Leave every photo in [todo] the Analyser has not seen in the face inbox,
  /// then ask it to look until everything left there has come back.

  Future<void> _scanWithAnalyser(List<MediaItem> todo) async {
    if (!await FaceInbox.isEnabled()) {
      _needsConsent = true;
      return;
    }

    // Whatever earlier runs found, as for photos added on another device or
    // left before the app closed, comes back first. Asking also starts a
    // run on anything already waiting in the inbox.

    _status = 'Asking the ${FaceAnalyser.displayName}...';
    _changed();
    await _collect();

    // What that filed is not sent again, nor is what is already waiting.

    final queued = await FaceInbox.queued();
    final toSend = [
      for (final item in todo)
        if (!_book.hasScanned(item.path) &&
            !queued.contains(faceKeyOf(item.path)))
          item,
    ];
    _toDo = toSend.length;
    _status = null;
    _changed();

    for (final item in toSend) {
      if (_cancelled) return;
      try {
        final image =
            await MediaRenditions.readLarge(item) ??
            await ThumbnailCache.instance.preview(item);
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
      if (_done % _askEvery == 0) await _collect();
    }

    await _collectAll();
  }

  /// Ask the Analyser to look until the inbox is empty and everything it
  /// found has been filed and acknowledged.

  Future<void> _collectAll() async {
    for (var runs = 0; runs < _maxRuns && !_cancelled; runs++) {
      final run = await _collect();
      if (run.pending == 0 && _ack.isEmpty) break;
    }
    _status = null;
  }

  /// One run: acknowledge what was filed since the last, then file what this
  /// one found, saving it to the faces file before it is acknowledged.

  Future<FaceAnalyserRun> _collect() async {
    final run = await FaceEngine.run(ack: _ack.toList());
    _ack.clear();
    _waiting = run.pending;
    _status = run.pending > 0
        ? 'The ${FaceAnalyser.displayName} has ${run.pending} '
              '${run.pending == 1 ? 'photo' : 'photos'} still to look at'
        : null;
    _changed();

    final url = run.resultUrl;
    if (run.waiting == 0 || url == null) return run;

    final results = await FaceEngine.readResults(url);
    final filed = <String>{};
    for (final entry in results.faces.entries) {
      if (_file(entry.key, entry.value)) filed.add(entry.key);
    }
    for (final key in results.failed.keys) {
      // A photo the Analyser could not read would fail again, so it counts
      // as looked at, with no faces.
      if (_file(key, const [])) {
        filed.add(key);
        _failed++;
      }
    }
    if (filed.isNotEmpty) await _save();

    // A result for a photo the album no longer has is acknowledged as well
    // once the whole album is known, so that it does not wait for ever.

    _ack.addAll(_knowsAll ? results.keys : filed);
    _changed();
    return run;
  }

  // File the faces found in the photo known by [key], returning whether
  // there was a photo to file them under. A photo this session does not
  // know of, as one added on another device, waits for the next scan of
  // People, which knows every photo.

  bool _file(String key, List<FoundFace> faces) {
    final path = _pathOf[key];
    if (path == null) return false;
    if (!_forgotten.contains(path)) {
      _book.addPhoto(path, faces, url: _urlOf[path]);
    }
    return true;
  }

  // A photo has just been left in the inbox as it was added: ask the
  // Analyser to look once the batch it came with is in.

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
      await _collectAll();
    } on Object catch (e) {
      debugPrint('PhotoPod: the Analyser could not look at new photos: $e');
    } finally {
      _scanning = false;
      _changed();
    }
  }
}
