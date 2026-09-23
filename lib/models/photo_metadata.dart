/// What a photo's own EXIF block says about it.
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

/// The details PhotoPod reads out of a photo itself, as opposed to the ones
/// the Solid server reports about the resource holding it.
///
/// Every field is optional, because a photo carries only the EXIF tags its
/// camera chose to write, and a PNG or GIF usually carries none at all.

class PhotoMetadata {
  /// Pixel width, after any EXIF rotation has been applied.

  final int? width;

  /// Pixel height, after any EXIF rotation has been applied.

  final int? height;

  /// When the shutter was pressed, which is rarely the same as the time the
  /// Pod records for the resource.

  final DateTime? taken;

  /// The camera manufacturer, such as `Apple`.

  final String? cameraMake;

  /// The camera model, such as `iPhone 15 Pro`.

  final String? cameraModel;

  /// The lens, when the camera records one.

  final String? lens;

  /// Shutter speed in seconds.

  final double? exposureSeconds;

  /// Aperture as an f-number.

  final double? aperture;

  /// Focal length in millimetres.

  final double? focalLength;

  /// Sensitivity, as an ISO number.

  final int? iso;

  /// Degrees north of the equator, negative for the southern hemisphere.

  final double? latitude;

  /// Degrees east of Greenwich, negative for the western hemisphere.

  final double? longitude;

  /// Height above sea level in metres.

  final double? altitude;

  const PhotoMetadata({
    this.width,
    this.height,
    this.taken,
    this.cameraMake,
    this.cameraModel,
    this.lens,
    this.exposureSeconds,
    this.aperture,
    this.focalLength,
    this.iso,
    this.latitude,
    this.longitude,
    this.altitude,
  });

  /// The same details with the pixel dimensions filled in.
  ///
  /// The width and height are taken from the decoded image rather than from
  /// EXIF, because a camera's `PixelXDimension` tag describes the frame
  /// before rotation and often disagrees with what is actually shown.

  PhotoMetadata copyWithSize({required int width, required int height}) =>
      PhotoMetadata(
        width: width,
        height: height,
        taken: taken,
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        lens: lens,
        exposureSeconds: exposureSeconds,
        aperture: aperture,
        focalLength: focalLength,
        iso: iso,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
      );

  /// Whether the photo says where it was taken, which is what puts it on the
  /// map.

  bool get hasLocation => latitude != null && longitude != null;

  /// Whether anything is known about the camera or the exposure.

  bool get hasCamera =>
      cameraMake != null ||
      cameraModel != null ||
      lens != null ||
      exposureSeconds != null ||
      aperture != null ||
      focalLength != null ||
      iso != null;

  /// Whether the photo carried nothing worth showing.

  bool get isEmpty =>
      width == null &&
      height == null &&
      taken == null &&
      !hasCamera &&
      !hasLocation;

  /// The camera as one line, such as `Apple iPhone 15 Pro`.

  String? get camera {
    final make = cameraMake?.trim();
    final model = cameraModel?.trim();
    if (make == null || make.isEmpty) return model;
    if (model == null || model.isEmpty) return make;

    // Most phones write the make into the model as well, and repeating it
    // would read as "Apple Apple iPhone".

    return model.toLowerCase().startsWith(make.toLowerCase())
        ? model
        : '$make $model';
  }

  /// The exposure as a photographer would write it, such as
  /// `1/250 s · f/1.8 · 26 mm · ISO 64`.

  String? get exposure {
    final parts = [
      if (exposureSeconds != null) formatShutterSpeed(exposureSeconds!),
      if (aperture != null) 'f/${_trim(aperture!)}',
      if (focalLength != null) '${_trim(focalLength!)} mm',
      if (iso != null) 'ISO $iso',
    ];
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  /// The coordinates as degrees with a hemisphere, such as
  /// `35.2809° S, 149.1300° E`.

  String? get coordinates => hasLocation
      ? '${formatCoordinate(latitude!, 'N', 'S')}, '
            '${formatCoordinate(longitude!, 'E', 'W')}'
      : null;

  static String _trim(double value) {
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0')
        ? rounded.substring(0, rounded.length - 2)
        : rounded;
  }
}

/// Render [seconds] the way a camera does: as a fraction below a second and
/// as a plain number above one.

String formatShutterSpeed(double seconds) {
  if (seconds <= 0) return '';
  if (seconds >= 1) {
    final whole = seconds.round();
    return (seconds - whole).abs() < 0.05
        ? '$whole s'
        : '${seconds.toStringAsFixed(1)} s';
  }
  return '1/${(1 / seconds).round()} s';
}

/// Render [degrees] to four decimal places with the hemisphere spelled out,
/// using [positive] for a positive value and [negative] for a negative one.

String formatCoordinate(double degrees, String positive, String negative) =>
    '${degrees.abs().toStringAsFixed(4)}° '
    '${degrees < 0 ? negative : positive}';

/// Convert an EXIF degrees/minutes/seconds triple into signed decimal
/// degrees, or null when the triple does not describe a real position.
///
/// [ref] is the EXIF hemisphere tag: `N`, `S`, `E` or `W`. A southern or
/// western reference makes the result negative. Coordinates outside the range
/// the Earth offers are rejected rather than clamped, because a photo with a
/// latitude of 300 has a damaged EXIF block and should not be put on a map.

double? dmsToDegrees(
  double degrees,
  double minutes,
  double seconds,
  String? ref, {
  required double limit,
}) {
  if (!degrees.isFinite || !minutes.isFinite || !seconds.isFinite) return null;

  final magnitude = degrees.abs() + minutes.abs() / 60 + seconds.abs() / 3600;
  if (magnitude > limit) return null;

  final hemisphere = (ref ?? '').trim().toUpperCase();
  final south = hemisphere.startsWith('S') || hemisphere.startsWith('W');
  final value = south ? -magnitude : magnitude;

  // A pair of exact zeroes is what a camera writes when it has no fix at
  // all, and Null Island is not where the photo was taken.

  return value == 0 ? null : value;
}

/// Parse an EXIF timestamp, which is written as `2026:09:22 14:05:33` in the
/// camera's own local time with no zone attached. Returns null for anything
/// else, including the all-zero stamp a camera writes when its clock has
/// never been set.

DateTime? parseExifDateTime(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;

  final match = RegExp(
    r'^(\d{4})[:\-](\d{2})[:\-](\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(text);
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (year < 1826 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  return DateTime(
    year,
    month,
    day,
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
}
