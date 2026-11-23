/// How People and Tags have TeePod look at photos, where it can be reached.
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

/// How many photos may be on their way to TeePod, or being looked at, at
/// once. Each is held in memory until its answer comes, to cut the faces
/// out of, so this bounds what a long run holds.

const int _inFlight = 8;

/// How many answers are filed between writes of the section's file, so
/// that a run cut short loses little, without a write for every photo.

const int _saveEvery = 10;

/// A photo sent to TeePod and not yet answered.

typedef _Sent = ({String path, String url, Uint8List picture});

extension _TeePodScan on AnalyserSection {
  /// Have TeePod look at every photo queued, including those chosen while it
  /// does, over one connection that has first proved itself (see
  /// [TeePod.connect]). Each photo is sent as its large rendition without
  /// where it was taken ([withoutMetadata]), as to the Pod Analyser, and
  /// each answer is filed as it comes, exactly as the Pod Analyser's are.
  /// Nothing is left in the Pod and nothing is shared.

  Future<void> _runTeePod(TeePodConfig config) async {
    _status = 'Checking that ${TeePodConfig.displayName} can be trusted...';
    _changed();
    final tee = await TeePod.connect(config);
    var counts = (answered: 0, next: 0);
    try {
      // Photos chosen after the last of a round was sent make another.

      while (_queue.isNotEmpty && !_cancelled) {
        counts = await _teePodRound(tee, counts);
      }
    } finally {
      await tee.close();
      _status = null;
      _changed();
    }
  }

  /// Send TeePod every photo queued, over one call, filing each answer as it
  /// comes, until the queue is empty. [counts] are how many photos have been
  /// answered so far, and the next photo's number; the new ones are returned.

  Future<({int answered, int next})> _teePodRound(
    TeePod tee,
    ({int answered, int next}) counts,
  ) async {
    final sent = <String, _Sent>{};
    final requests = StreamController<TeePodImage>();
    final unfiled = <String>{};
    var answered = counts.answered;
    var next = counts.next;
    var stopped = false;
    Completer<void>? room;

    void progress() {
      _status =
          '${TeePodConfig.displayName} has looked at $answered of $_toDo '
          '${_toDo == 1 ? 'photo' : 'photos'}';
      _changed();
    }

    void makeRoom() {
      final waiting = room;
      room = null;
      if (waiting != null && !waiting.isCompleted) waiting.complete();
    }

    // Read each photo queued and send it, a few at a time.

    Future<void> send() async {
      try {
        while (_queue.isNotEmpty && !_cancelled && !stopped) {
          while (sent.length >= _inFlight && !stopped) {
            await (room ??= Completer<void>()).future;
          }
          if (stopped) break;
          final item = _queue.removeAt(0);
          try {
            final image =
                await MediaRenditions.readLarge(item) ??
                await _renderLarge(item);
            if (image == null) throw StateError('no picture');
            final bare = withoutMetadata(image);
            if (bare == null) throw StateError('not a JPEG or PNG picture');
            final id = '${next++}';
            sent[id] = (path: item.path, url: item.url, picture: bare);
            requests.add((id: id, image: bare));
          } on Object catch (e) {
            _failed++;
            answered++;
            debugPrint(
              'PhotoPod: could not send ${item.url} to '
              '${TeePodConfig.displayName}: $e',
            );
            progress();
          }
        }
      } finally {
        await requests.close();
      }
    }

    progress();
    final sending = send();
    try {
      await for (final answer in tee.analyse(requests.stream, teePodService)) {
        final photo = sent.remove(answer.id);
        makeRoom();
        if (photo == null) continue;
        answered++;
        if (!_forgotten.contains(photo.path)) {
          try {
            final content = await teePodAnswer(answer, photo.picture);
            if (fileAnswer(photo.path, content, url: photo.url)) _failed++;
            unfiled.add(photo.path);
          } on Object catch (e) {
            _failed++;
            debugPrint(
              'PhotoPod: could not file the answer for '
              '${photo.url}: $e',
            );
          }
        }
        progress();
        if (_cancelled) break;
        if (unfiled.length >= _saveEvery) await _fileAnswered(unfiled);
      }
    } finally {
      // Photos sent and not answered, as when the connection is lost, stay
      // under Unprocessed, to be asked about again.

      stopped = true;
      makeRoom();
      await sending;

      // After a logout ([reset]) there is nothing left to save to, and
      // saving would write the emptied section over the user's file.

      if (!_cancelled) await _fileAnswered(unfiled);
    }
    return (answered: answered, next: next);
  }

  /// Save the file with the answers filed for [paths], and tell the catalog
  /// what was found in them, as for the Pod Analyser's answers.

  Future<void> _fileAnswered(Set<String> paths) async {
    if (paths.isEmpty) return;
    final photos = {...paths};
    paths.clear();
    try {
      photos.addAll(await fromCatalog());
      await save();
      await toCatalog(photos);
    } on Object catch (e) {
      _error = 'Could not save the $lookingFor found: $e';
      debugPrint('PhotoPod: $_error');
    }
    _changed();
  }
}
