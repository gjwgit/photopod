/// What the filter bar is searching for, and whether an item matches it.
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
/// Authors: Graham Williams

library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:photopod/models/catalog_entry.dart';
import 'package:photopod/models/media_item.dart';

/// What a search term looks at.

enum SearchField { keyword, person, tag, location, date, title, name }

/// The words that pick a field, as typed before the colon. Anything else
/// before a colon is searched for as it stands, so a name with a colon in it
/// can still be found.

const Map<String, SearchField> searchPrefixes = {
  'person': SearchField.person,
  'people': SearchField.person,
  'face': SearchField.person,
  'tag': SearchField.tag,
  'location': SearchField.location,
  'loc': SearchField.location,
  'date': SearchField.date,
  'title': SearchField.title,
  'name': SearchField.name,
};

/// How far from a point given as `location:lat,lon` a photo can be, in
/// kilometres, when no distance is given.

const double defaultSearchRadiusKm = 10;

const List<String> _months = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// One term of a search, such as `tag:beach` or `-person:"Jane Doe"`.

class SearchTerm {
  const SearchTerm(this.field, this.value, {this.negated = false});

  final SearchField field;

  /// What follows the colon, lower case, without its quotes.

  final String value;

  /// Whether the term was written with a leading `-`, to leave out what it
  /// matches.

  final bool negated;
}

/// A search typed into the filter bar.
///
/// Terms are separated by spaces and an item must match every one of them.
/// A term on its own is a keyword, found in the item's name, title, tags,
/// people or place. A term can instead name what it looks at:
///
/// * `person:jane`, the people named in the photo;
/// * `tag:beach`, its tags;
/// * `title:sunset`, its title;
/// * `name:IMG_`, its file name;
/// * `date:2026`, `date:2026-10`, `date:2026-10-17`, `date:october`, or a
///   range such as `date:2025-12..2026-02`, either end of which can be left
///   open;
/// * `location:` or `location:yes` for photos that say where they were
///   taken, `location:no` for those that do not, `location:lat,lon` or
///   `location:lat,lon,km` for those taken near a point, and anything else,
///   such as `location:canberra`, for those given a place of that name.
///
/// Quotes keep spaces in a term, as in `person:"Jane Doe"`, and a leading
/// `-` leaves out what a term matches.

class MediaSearch {
  MediaSearch._(this.terms, this.problems);

  /// A search for [text].

  factory MediaSearch.parse(String text) {
    final terms = <SearchTerm>[];
    final problems = <String>[];
    for (final token in _tokens(text)) {
      var rest = token;
      final negated = rest.length > 1 && rest.startsWith('-');
      if (negated) rest = rest.substring(1);

      final colon = rest.indexOf(':');
      final field = colon > 0
          ? searchPrefixes[rest.substring(0, colon).toLowerCase()]
          : null;
      final value = _unquote(
        field == null ? rest : rest.substring(colon + 1),
      ).toLowerCase();

      if (field == SearchField.date && _dateRange(value) == null) {
        problems.add(
          'Dates look like 2026, 2026-10, 2026-10-17 or october, or a range '
          'such as 2025..2026',
        );
      } else if (field != null || value.isNotEmpty) {
        terms.add(
          SearchTerm(field ?? SearchField.keyword, value, negated: negated),
        );
      }
    }
    return MediaSearch._(terms, problems);
  }

  /// The terms every item must match.

  final List<SearchTerm> terms;

  /// What is wrong with any term that could not be understood. Such a term
  /// is left out of the search rather than hiding everything.

  final List<String> problems;

  /// Whether there is nothing to search for, so everything is shown.

  bool get isEmpty => terms.isEmpty;

  /// Whether [item] matches every term, given what the catalog says about
  /// it in [entry].

  bool matches(MediaItem item, CatalogEntry? entry) =>
      terms.every((term) => _matches(term, item, entry) != term.negated);

  static bool _matches(SearchTerm term, MediaItem item, CatalogEntry? entry) {
    final value = term.value;
    bool has(String? text) =>
        text != null && text.toLowerCase().contains(value);
    final tags = entry?.tags ?? const <PhotoTag>[];
    final faces = entry?.faces ?? const <PhotoFace>[];
    final title = entry?.title?.text;
    final place = entry?.place?.name;

    switch (term.field) {
      case SearchField.keyword:
        return has(item.name) ||
            has(title) ||
            has(place) ||
            tags.any((tag) => has(tag.label)) ||
            faces.any((face) => has(face.name));
      case SearchField.name:
        return has(item.name);
      case SearchField.title:
        return value.isEmpty ? title != null : has(title);
      case SearchField.tag:
        return value.isEmpty ? tags.isNotEmpty : tags.any((t) => has(t.label));
      case SearchField.person:
        return value.isEmpty
            ? faces.isNotEmpty
            : faces.any((face) => has(face.name));
      case SearchField.date:
        final date = item.date;
        return date != null && _dateRange(value)!.contains(date);
      case SearchField.location:
        return _nearby(value, entry?.location) ?? has(place);
    }
  }

  // Split on spaces, except within double quotes.

  static Iterable<String> _tokens(String text) => RegExp(
    r'(?:[^\s"]+|"[^"]*"?)+',
  ).allMatches(text).map((match) => match.group(0)!);

  static String _unquote(String text) => text.replaceAll('"', '').trim();

  static const Set<String> _yes = {'', 'yes', 'any'};
  static const Set<String> _no = {'no', 'none'};

  // Whether [location] is known, or near the point [value] names, or null
  // when [value] is neither and so is the name of a place.

  static bool? _nearby(String value, (double, double)? location) {
    if (_yes.contains(value)) return location != null;
    if (_no.contains(value)) return location == null;
    final point = _point(value);
    if (point == null) return null;
    return location != null &&
        _distanceKm(point.$1, point.$2, location.$1, location.$2) <= point.$3;
  }

  // A point as `lat,lon` or `lat,lon,km`.

  static (double, double, double)? _point(String value) {
    final parts = value.split(',').map((part) => double.tryParse(part.trim()));
    final numbers = parts.toList();
    if (numbers.length < 2 || numbers.length > 3) return null;
    if (numbers.any((number) => number == null)) return null;
    final latitude = numbers[0]!;
    final longitude = numbers[1]!;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    final km = numbers.length == 3 ? numbers[2]! : defaultSearchRadiusKm;
    return km < 0 ? null : (latitude, longitude, km);
  }

  // The great circle distance between two points, in kilometres.

  static double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    double radians(double degrees) => degrees * math.pi / 180;
    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(radians(lat1)) *
            math.cos(radians(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return 6371 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static _DateRange? _dateRange(String value) {
    final month = _monthOf(value);
    if (month != null) return _DateRange.month(month);
    if (!value.contains('..')) {
      final period = _period(value);
      return period == null ? null : _DateRange(period.$1, period.$2);
    }
    final ends = value.split('..');
    if (ends.length != 2 || (ends[0].isEmpty && ends[1].isEmpty)) return null;
    final from = ends[0].isEmpty ? null : _period(ends[0]);
    final to = ends[1].isEmpty ? null : _period(ends[1]);
    if ((ends[0].isNotEmpty && from == null) ||
        (ends[1].isNotEmpty && to == null)) {
      return null;
    }
    return _DateRange(from?.$1, to?.$2);
  }

  // A month by name, or its first three letters.

  static int? _monthOf(String value) {
    if (value.length < 3) return null;
    final index = _months.indexWhere((month) => month.startsWith(value));
    return index < 0 ? null : index + 1;
  }

  // The year, month or day [value] names, as the moment it starts and the
  // moment after it ends.

  static (DateTime, DateTime)? _period(String value) {
    final match = RegExp(
      r'^(\d{4})(?:[-/](\d{1,2})(?:[-/](\d{1,2}))?)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = match.group(2) == null ? null : int.parse(match.group(2)!);
    final day = match.group(3) == null ? null : int.parse(match.group(3)!);
    if (month != null && (month < 1 || month > 12)) return null;
    if (day != null && (day < 1 || day > DateTime(year, month! + 1, 0).day)) {
      return null;
    }
    if (day != null) {
      return (DateTime(year, month!, day), DateTime(year, month, day + 1));
    }
    if (month != null) {
      return (DateTime(year, month), DateTime(year, month + 1));
    }
    return (DateTime(year), DateTime(year + 1));
  }
}

/// A span of time, open at either end, or a month of any year.

class _DateRange {
  const _DateRange(this.from, this.until) : month = null;

  const _DateRange.month(this.month) : from = null, until = null;

  final DateTime? from;
  final DateTime? until;
  final int? month;

  bool contains(DateTime date) {
    final local = date.toLocal();
    if (month != null) return local.month == month;
    return (from == null || !local.isBefore(from!)) &&
        (until == null || local.isBefore(until!));
  }
}

/// The search typed into the filter bar, shared by every section so that it
/// stays in place when moving between them.

class MediaFilter extends ChangeNotifier {
  String _text = '';
  MediaSearch _search = MediaSearch.parse('');

  /// What was typed.

  String get text => _text;

  /// What was typed, understood.

  MediaSearch get search => _search;

  /// Whether anything is being filtered out.

  bool get isActive => !_search.isEmpty;

  set text(String text) {
    if (text == _text) return;
    _text = text;
    _search = MediaSearch.parse(text);
    notifyListeners();
  }

  void clear() => text = '';
}
