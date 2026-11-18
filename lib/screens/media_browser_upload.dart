/// Adding photos and videos to the Pod, and the duplicates found on the way.
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

/// A file on its way into the Pod: the name it arrived with, how to read its
/// bytes, and how to learn when it was last changed, which is all the picker
/// and a desktop drop have in common.

typedef _Upload = ({
  String name,
  Future<Uint8List> Function() read,
  Future<DateTime> Function() modified,
});

/// The renditions made of a file before it goes up: a photo's, or the
/// opening frame of a video.

typedef _Renditions = ({PhotoRenditions? photo, Uint8List? frame});

/// A file read and ready to go up: the [upload] it came from, the [name] it
/// will be stored under, its [bytes] and their SHA-256 [hash], its
/// [renditions], and [when] it was taken, as best that can be told.

typedef _Prepared = ({
  _Upload upload,
  String name,
  Uint8List bytes,
  String hash,
  _Renditions renditions,
  DateTime? when,
});

/// What the catalog would hold for a [_Prepared] file, as it is compared
/// with, and merged into, the copy already in the Pod.

extension on _Prepared {
  CatalogEntry get entry => CatalogEntry(
    '',
    name: name,
    taken: when == null ? null : encodeDate(when!),
    metadata: renditions.photo?.metadata,
    hash: hash,
  );
}

/// A file being added that is the same as one in the Pod, catalogued as
/// [inPod].

typedef _Duplicate = ({_Prepared file, CatalogEntry inPod});

/// Adding files from this device, by the Add button or by dropping them on
/// the Library, and settling any that turn out to be in the Pod already.

extension MediaBrowserUpload on MediaBrowserState {
  /// Add files from this device to the album.
  ///
  /// The picker accepts photos and videos alike, since the Library shows both
  /// together. Each file keeps the name it had, in whatever script, and is
  /// stored under a random name of its own.

  Future<void> _addFiles(BuildContext context) async {
    if (await _needsPod(context, 'add photos and videos')) return;
    if (!context.mounted) return;

    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [...photoExtensions, ...videoExtensions],
        dialogTitle: 'Add photos and videos',
      );
    } on Object catch (e) {
      if (context.mounted) {
        await showErrorDialog(context, 'Could not open the file picker', '$e');
      }
      return;
    }

    if (picked.isEmpty || !context.mounted) return;

    await _upload(context, [
      for (final file in picked)
        (
          name: file.name,
          read: file.readAsBytes,
          modified: file.xFile.lastModified,
        ),
    ]);
  }

  /// Add the files dragged from the desktop and dropped onto the Library.
  ///
  /// A dropped folder is not unpacked, since what is in it would need an
  /// album of its own. It is reported instead, along with anything else that
  /// could not be added.

  Future<void> _dropFiles(BuildContext context, List<DropItem> dropped) async {
    if (dropped.isEmpty) return;
    if (await _needsPod(context, 'add photos and videos')) return;
    if (!context.mounted) return;

    final folders = dropped.whereType<DropItemDirectory>().toList();
    final files = dropped.where((item) => item is! DropItemDirectory).toList();

    if (files.isNotEmpty) {
      await _upload(context, [
        for (final file in files)
          (
            name: file.name,
            read: () => _inDropScope(file, file.readAsBytes),
            modified: () => _inDropScope(file, file.lastModified),
          ),
      ]);
    }

    if (folders.isNotEmpty && context.mounted) {
      await showErrorDialog(
        context,
        folders.length == 1
            ? 'A folder was not added'
            : 'Some folders were not added',
        'Only photos and videos can be dropped here. Open the folder and '
        'drag the files inside it instead, then put them into an album.\n\n'
        '${folders.map((folder) => folder.name).join('\n')}',
      );
    }
  }

  // A sandboxed macOS build may only read a dropped file inside the security
  // scope the drop handed over with it. Elsewhere there is no bookmark, and
  // the file is simply read.

  static Future<T> _inDropScope<T>(
    DropItem file,
    Future<T> Function() read,
  ) async {
    final bookmark = file.extraAppleBookmark;
    if (bookmark == null || bookmark.isEmpty) return read();

    await DesktopDrop.instance.startAccessingSecurityScopedResource(
      bookmark: bookmark,
    );
    try {
      return await read();
    } finally {
      await DesktopDrop.instance.stopAccessingSecurityScopedResource(
        bookmark: bookmark,
      );
    }
  }

  /// Write [files] into the store, then report anything that was refused,
  /// renamed or found to be in the Pod already on the way.
  ///
  /// Shared by the Add button and by dropping files onto the Library, so that
  /// both treat names, unsupported files, duplicates and failures in the
  /// same way.
  ///
  /// Each file is checked against what is in the Pod before it goes up,
  /// including the files added earlier in the same batch. When it is an
  /// exact copy of one, the user is shown the details of both and asked
  /// whether to merge them, keeping only the photo already there; see
  /// [showDuplicateDialog]. The progress spinner is taken down while they
  /// decide, and put up again for the rest of the files.

  Future<void> _upload(BuildContext context, List<_Upload> files) async {
    // Everything is written encrypted, so the security key has to be in hand
    // before the first file goes up rather than part way through the batch.

    if (!await _ensureSecurityKey(context)) return;
    if (!context.mounted) return;

    final favourites = context.read<Favourites>();
    final albums = context.read<Albums>();

    final failed = <String, String>{};
    final renamed = <String, String>{};
    var added = 0;
    var merged = 0;
    var skipped = 0;

    // The choice the user asked to have made for every further duplicate,
    // if they did.

    DuplicateChoice? always;

    Future<void> store(_Prepared file) async {
      await _store(file);
      if (file.name != file.upload.name) renamed[file.upload.name] = file.name;
      added++;
    }

    Future<void> settle(
      _Prepared file,
      CatalogEntry inPod,
      DuplicateChoice choice,
    ) async {
      switch (choice) {
        case DuplicateChoice.merge:
          await MediaCatalog.mergeInto(inPod.path, file.entry);
          merged++;
        case DuplicateChoice.keepBoth:
          await store(file);
        case DuplicateChoice.skip:
          skipped++;
      }
    }

    var next = 0;
    while (next < files.length) {
      if (!context.mounted) break;

      // Add files until one turns out to be in the Pod already and the user
      // has to be asked about it.

      final found = await showWorking<_Duplicate?>(
        context,
        'Adding to your Pod...',
        () async {
          while (next < files.length) {
            final upload = files[next++];
            try {
              if (kindOf(upload.name) == null) {
                failed[upload.name] = 'not a photo or video PhotoPod supports';
                continue;
              }
              final file = await _prepare(upload);
              final inPod = await MediaDuplicates.find(
                hash: file.hash,
                name: file.name,
                taken: file.when,
              );
              if (inPod == null) {
                await store(file);
              } else if (always == null) {
                return (file: file, inPod: inPod);
              } else {
                await settle(file, inPod, always);
              }
            } on Object catch (e) {
              failed[upload.name] = '$e';
            }
          }
          return null;
        },
      );
      if (found == null || !context.mounted) break;

      final item = await MediaDuplicates.itemFor(found.inPod);
      if (!context.mounted) break;
      final answer = await showDuplicateDialog(
        context,
        item: item,
        inPod: found.inPod,
        incoming: found.file.entry,
        incomingPicture:
            found.file.renditions.photo?.small ?? found.file.renditions.frame,
        favourite: favourites.contains(item),
        albums: [
          for (final name in albums.names)
            if (albums.contains(name, item)) name,
        ],
        more: next < files.length,
      );
      if (answer.forAll) always = answer.choice;
      if (!context.mounted) break;

      try {
        await showWorking(
          context,
          answer.choice == DuplicateChoice.merge
              ? 'Merging...'
              : 'Adding to your Pod...',
          () => settle(found.file, found.inPod, answer.choice),
        );
      } on Object catch (e) {
        failed[found.file.upload.name] = '$e';
      }
    }

    if ((added > 0 || merged > 0) && context.mounted) {
      context.read<MediaIndex>().invalidate();
    }
    await reload();
    if (!context.mounted) return;

    // Say what became of the duplicates, so that a file the user picked and
    // cannot see as a tile of its own is not taken to have gone missing.

    if (merged > 0 || skipped > 0) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(_duplicatesReport(merged, skipped))),
      );
    }

    if (failed.isNotEmpty) {
      await showErrorDialog(
        context,
        added == 0 && merged == 0
            ? 'Nothing could be added'
            : 'Some files were not added',
        failed.entries.map((e) => '${e.key}: ${e.value}').join('\n\n'),
      );
      return;
    }

    // A name is quietly adjusted rather than refused, so that a photo always
    // lands. Saying so beats letting the user wonder why the name on the tile
    // is not the one they picked.

    if (renamed.isNotEmpty && context.mounted) {
      await showErrorDialog(
        context,
        renamed.length == 1
            ? 'One file was renamed'
            : 'Some files were renamed',
        'The name held a character no file name can '
        '(/ \\ : * ? " < > |).\n\n'
        '${renamed.entries.map((e) => '${e.key}  →  ${e.value}').join('\n')}',
      );
    }
  }

  // A sentence on how many duplicates were [merged] into the photos already
  // in the Pod, and how many were [skipped].

  static String _duplicatesReport(int merged, int skipped) {
    String count(int n) => n == 1 ? 'One duplicate was' : '$n duplicates were';
    return [
      if (merged > 0)
        '${count(merged)} merged into what is already in your Pod.',
      if (skipped > 0) '${count(skipped)} not added.',
    ].join(' ');
  }

  // Read [upload] and get it ready to go up: its name made safe, the digest
  // that tells whether it is already in the Pod, and its renditions.
  //
  // The renditions are made before the file goes up, since making a photo's
  // is also when its EXIF block is read, and that says when it was taken.
  // Without one, the time the file was last changed on this device is the
  // next best thing: the Pod would otherwise only know when it was uploaded.

  static Future<_Prepared> _prepare(_Upload upload) async {
    final name = safeFileName(upload.name);
    final bytes = await upload.read();
    final hash = await hashContent(bytes);
    final renditions = await _makeRenditions(name, bytes);
    final when = renditions.photo?.metadata?.taken ?? await _modifiedOf(upload);
    return (
      upload: upload,
      name: name,
      bytes: bytes,
      hash: hash,
      renditions: renditions,
      when: when,
    );
  }

  // Put [file] into the store under a fresh random name.

  static Future<void> _store(_Prepared file) async {
    final path = await MediaStore.newPath(file.name);

    // The catalog entry goes first: one whose file never arrives is never
    // matched, while a file without its name would show under the random
    // one. The EXIF details go in with it, so the map need not read the
    // photo back, and the digest, so that a later copy is known for one.

    await MediaCatalog.set(
      path,
      file.name,
      taken: file.when,
      metadata: file.renditions.photo?.metadata,
      hash: file.hash,
    );
    await PodMediaService.writeMedia(
      path: path,
      bytes: file.bytes,
      name: file.name,
    );
    await _saveRenditions(path, file.name, file.renditions);
  }

  // When [file] was last changed on this device, or null where that cannot
  // be learnt. A browser that does not know reports the epoch, which is
  // treated as not knowing.

  static Future<DateTime?> _modifiedOf(_Upload file) async {
    try {
      final modified = await file.modified();
      return modified.millisecondsSinceEpoch <= 0 ? null : modified.toUtc();
    } on Object catch (e) {
      debugPrint('PhotoPod: could not tell when ${file.name} was changed: $e');
      return null;
    }
  }

  // Make the renditions of the photo or video [name] while its [bytes] are
  // still in hand, so that the grid and the preview never need the original.
  // For a video that is its opening frame. Renditions that cannot be made
  // are not counted as a failure; a photo has them made the first time it is
  // looked at instead, and a video keeps the film glyph.

  static Future<_Renditions> _makeRenditions(
    String name,
    Uint8List bytes,
  ) async {
    try {
      if (kindOf(name) == MediaKind.video) {
        return (photo: null, frame: await firstFrameThumbnail(bytes, name));
      }
      final photo = await compute(renderPhoto, (
        bytes: bytes,
        keepOriginal: isGif(name),
      ));
      return (photo: photo, frame: null);
    } on Object catch (e) {
      debugPrint('PhotoPod: could not make renditions of $name: $e');
      return (photo: null, frame: null);
    }
  }

  // Store [renditions] beside the file just added at [path]. The file is
  // already safely on the Pod, so a failure here is only logged.

  static Future<void> _saveRenditions(
    String path,
    String name,
    _Renditions renditions,
  ) async {
    try {
      final photo = renditions.photo;
      final frame = renditions.frame;
      if (photo != null) await MediaRenditions.savePhoto(path, photo);
      if (frame != null) await MediaRenditions.saveVideo(path, frame);
    } on Object catch (e) {
      debugPrint('PhotoPod: could not store renditions of $name: $e');
    }
  }
}
