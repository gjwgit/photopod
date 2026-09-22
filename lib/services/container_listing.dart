/// Read a Solid container listing.
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

/// One entry parsed out of a container listing.

class ListingEntry {
  /// The name exactly as it appears in the listing, still percent-encoded and
  /// with the trailing slash that marks a container.

  final String rawName;

  /// Whether the entry is a container rather than a file.

  final bool isContainer;

  /// When the server last recorded a change, if it says.

  final DateTime? modified;

  /// Size in bytes, if the server says.

  final int? size;

  const ListingEntry({
    required this.rawName,
    required this.isContainer,
    this.modified,
    this.size,
  });
}

// Predicates a Community Solid Server publishes alongside each entry. They
// are matched loosely so that the prefixed form (posix:mtime), the alternative
// prefix (stat:mtime) and a full IRI all work.

final RegExp _mtime = RegExp(r'mtime\s+([0-9]+(?:\.[0-9]+)?)');
final RegExp _size = RegExp(r'size\s+([0-9]+)');
final RegExp _modified = RegExp(r'modified\s+"([^"]+)"');
final RegExp _subject = RegExp('^<([^>]*)>');

/// Parse the Turtle body of a GET on a container into its entries.
///
/// A Solid container listing is Turtle, but the shapes servers emit are
/// regular enough that reading them line by line is both reliable and far
/// cheaper than a full RDF parse — the same approach solidpod itself takes,
/// extended here to pick up the modification time and size that the grid and
/// the detailed list need for sorting and display.
///
/// A resource is not confined to a single Turtle statement: a Community Solid
/// Server writes the type triple in one statement and the `posix:mtime`,
/// `posix:size` and `dcterms:modified` triples in another. Entries are
/// therefore accumulated by subject and merged, so that each resource is
/// returned exactly once however many statements describe it, in the order
/// the listing first mentions it.
///
/// Statements about the container itself, written with an empty subject
/// `<>`, are skipped.

List<ListingEntry> parseContainerListing(String body) {
  final found = <String, _Entry>{};

  String? name;

  void scan(String line) {
    final entry = found[name];
    if (entry == null) return;

    final mtimeMatch = _mtime.firstMatch(line);
    if (mtimeMatch != null) {
      final seconds = double.tryParse(mtimeMatch.group(1)!);
      if (seconds != null) {
        entry.mtime ??= DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round(),
          isUtc: true,
        ).toLocal();
      }
    }

    final modifiedMatch = _modified.firstMatch(line);
    if (modifiedMatch != null) {
      final parsed = DateTime.tryParse(modifiedMatch.group(1)!);
      if (parsed != null) entry.modified ??= parsed.toLocal();
    }

    final sizeMatch = _size.firstMatch(line);
    if (sizeMatch != null) entry.size ??= int.tryParse(sizeMatch.group(1)!);
  }

  for (final raw in body.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('@') || line.startsWith('#')) continue;

    if (name == null) {
      final match = _subject.firstMatch(line);

      // A line that does not open a new subject while none is open belongs to
      // a statement we have already finished with, so there is nothing to do.

      if (match == null) continue;

      final subject = match.group(1)!;

      // Skip the container's own statements, and anything a second statement
      // has already introduced — the latter is merged into rather than
      // replacing what is known about that resource.

      if (subject.isNotEmpty && subject != '/') {
        name = subject;
        final entry = found.putIfAbsent(subject, _Entry.new);
        if (line.contains('ldp:Container')) entry.isContainer = true;
      }
    }

    scan(line);

    // Turtle statements end in a full stop; a semicolon or comma means the
    // predicates continue on the following line.

    if (line.endsWith('.')) name = null;
  }

  return [
    for (final subject in found.keys)
      ListingEntry(
        rawName: subject,
        isContainer: found[subject]!.isContainer,

        // A server that gives both prefers the dcterms date, which is an
        // explicit timestamp rather than a file system mtime.
        modified: found[subject]!.modified ?? found[subject]!.mtime,
        size: found[subject]!.size,
      ),
  ];
}

// What is known so far about one subject, across every statement describing
// it. The first value seen for each field wins, so a later statement can fill
// a gap but never contradict what has already been read.

class _Entry {
  bool isContainer = false;
  DateTime? mtime;
  DateTime? modified;
  int? size;
}
