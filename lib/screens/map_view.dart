/// The photos in the album, shown where they were taken.
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

import 'package:flutter_map/flutter_map.dart';
import 'package:gap/gap.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:solidpod/solidpod.dart' show KeyManager;
import 'package:solidui/solidui.dart' show getKeyFromUserIfRequired;

import 'package:photopod/dialogs/preview_dialog.dart';
import 'package:photopod/models/media_item.dart';
import 'package:photopod/models/photo_metadata.dart';
import 'package:photopod/services/media_index.dart';
import 'package:photopod/services/pod_keys.dart';
import 'package:photopod/services/thumbnail_cache.dart';
import 'package:photopod/widgets/media_thumbnail.dart';

/// How many photos the map will read before it stops looking.
///
/// Finding a photo's coordinates means fetching it from the Pod, decrypting
/// it and decoding it, so a very large album would otherwise keep the network
/// busy for a long time. The map says when it has stopped early.

const int maxMappedPhotos = 600;

/// Coordinates rounded to this many decimal places count as the same place.
/// Four places is about eleven metres, which is close enough that two markers
/// would sit on top of one another.

const int _clusterPrecision = 4;

/// The tiles the map is drawn from.

const String _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// The Maps section: every geotagged photo in the album on one map.
///
/// The album index says which photos there are; their coordinates come from
/// each photo's own EXIF block, which is read through the same cache that
/// feeds the grid, so a photo already looked at costs nothing to place.

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _map = MapController();

  /// The photos that turned out to carry coordinates, grouped by place.

  List<_Place> _places = const [];

  /// How many photos have been read so far, and how many there are to read.

  int _read = 0;
  int _toRead = 0;

  bool _scanning = false;
  bool _disposed = false;
  bool _fitted = false;
  String? _error;

  /// Which scan of the album the current markers belong to, so that the
  /// photos are not read again until the album itself has changed.

  DateTime? _scannedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _start() async {
    final index = context.read<MediaIndex>();
    await index.refresh();
    if (!mounted) return;
    await _readLocations();
  }

  /// Read the coordinates out of every photo the index knows about.

  Future<void> _readLocations({bool force = false}) async {
    final index = context.read<MediaIndex>();
    if (_scanning) return;
    if (!force && _scannedAt != null && _scannedAt == index.scannedAt) return;

    final photos = index.photos.take(maxMappedPhotos).toList();

    setState(() {
      _scanning = true;
      _error = null;
      _read = 0;
      _toRead = photos.length;
      if (force) _places = const [];
    });

    // Every photo PhotoPod wrote is encrypted, so the security key has to be
    // in hand before the first one can be decoded.

    if (photos.any((photo) => photo.isEncrypted)) {
      try {
        await getKeyFromUserIfRequired(
          context,
          const Text('Please enter your security key to map your photos'),
        );
        if (!await KeyManager.hasSecurityKey()) {
          throw Exception('The security key is needed to read your photos.');
        }

        // Read the keys into memory before the batches start, so that four
        // concurrent reads do not each try to read them.

        await PodKeys.prime();
      } on Object catch (e) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _error = '$e';
          });
        }
        return;
      }
    }

    final located = <MediaItem, PhotoMetadata>{};

    // A few at a time, which is what the Pod answers best, and which lets the
    // map fill in as the photos come back rather than all at the end.

    for (var start = 0; start < photos.length; start += thumbnailConcurrency) {
      if (_disposed) return;

      final batch = photos.skip(start).take(thumbnailConcurrency).toList();
      final results = await Future.wait(
        batch.map(ThumbnailCache.instance.metadata),
      );

      for (var i = 0; i < batch.length; i++) {
        final metadata = results[i];
        if (metadata != null && metadata.hasLocation) {
          located[batch[i]] = metadata;
        }
      }

      if (_disposed || !mounted) return;
      setState(() {
        _read = start + batch.length;
        _places = _group(located);
      });
    }

    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scannedAt = index.scannedAt;
    });
    _fit();
  }

  /// Bring every marker into view, once, when the first ones arrive.

  void _fit() {
    if (_fitted || _places.isEmpty) return;
    _fitted = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: _places.map((place) => place.point).toList(),
          padding: const EdgeInsets.all(56),
          maxZoom: 15,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = context.watch<MediaIndex>();

    return Column(
      children: [
        _buildStatusBar(context, index),
        const Divider(height: 1),
        Expanded(child: _buildMap(context, index)),
      ],
    );
  }

  Widget _buildStatusBar(BuildContext context, MediaIndex index) {
    final photos = _places.fold(0, (sum, place) => sum + place.items.length);
    final busy = _scanning || index.isLoading;

    final summary = busy
        ? 'Reading your photos...  $_read of $_toRead'
        : photos == 0
        ? 'No photos with a location yet'
        : '$photos ${photos == 1 ? 'photo' : 'photos'} in '
              '${_places.length} ${_places.length == 1 ? 'place' : 'places'}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Expanded(
            child: Text(summary, style: Theme.of(context).textTheme.bodySmall),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen_outlined),
            tooltip: 'Show every place',
            onPressed: _places.isEmpty
                ? null
                : () {
                    _fitted = false;
                    _fit();
                  },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Read the album again',
            onPressed: busy
                ? null
                : () async {
                    await index.refresh(force: true);
                    if (mounted) await _readLocations(force: true);
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context, MediaIndex index) {
    final error = _error ?? index.error;
    if (error != null && _places.isEmpty) {
      return _buildMessage(
        context,
        icon: Icons.cloud_off,
        title: 'Could not read your album',
        message: error,
      );
    }

    if (_places.isEmpty && !_scanning && !index.isLoading) {
      return _buildMessage(
        context,
        icon: Icons.location_off_outlined,
        title: 'Nothing to map yet',
        message: index.photos.isEmpty
            ? 'Add some photos to your album and any that were taken with '
                  'location services switched on will appear here.'
            : 'None of the photos in your album carry GPS coordinates. A '
                  'camera only writes them when location services are '
                  'switched on, and some applications strip them out when a '
                  'photo is exported or shared.',
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: const MapOptions(
            initialCenter: LatLng(-35.2809, 149.13),
            initialZoom: 3,
            minZoom: 2,
            maxZoom: 18,
          ),
          children: [
            TileLayer(
              urlTemplate: _tileUrl,
              userAgentPackageName: 'au.solidcommunity.photopod',
              maxNativeZoom: 19,
            ),
            MarkerLayer(
              markers: [
                for (final place in _places)
                  Marker(
                    point: place.point,
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    child: _PlaceMarker(
                      place: place,
                      onTap: () => _open(context, place),
                    ),
                  ),
              ],
            ),
            const SimpleAttributionWidget(
              source: Text('OpenStreetMap contributors'),
            ),
          ],
        ),
        if (index.isTruncated)
          const Positioned(
            left: 12,
            top: 12,
            child: _Notice(
              text:
                  'Only the first $maxScannedFolders folders were read, so '
                  'some places may be missing.',
            ),
          ),
      ],
    );
  }

  // Tapping a marker opens the photo taken there, or asks which one when
  // several share the spot.

  Future<void> _open(BuildContext context, _Place place) async {
    if (place.items.length == 1) {
      await showPreviewDialog(context, place.items.first);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _PlaceDialog(place: place),
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const Gap(16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ],
      ),
    ),
  );

  // Photos taken within about eleven metres of each other share a marker,
  // which is what keeps a whole afternoon in one garden from turning into a
  // pile of overlapping pins.

  static List<_Place> _group(Map<MediaItem, PhotoMetadata> located) {
    final groups = <String, List<MediaItem>>{};
    final points = <String, LatLng>{};

    for (final entry in located.entries) {
      final latitude = entry.value.latitude!;
      final longitude = entry.value.longitude!;
      final key =
          '${latitude.toStringAsFixed(_clusterPrecision)},'
          '${longitude.toStringAsFixed(_clusterPrecision)}';

      groups.putIfAbsent(key, () => <MediaItem>[]).add(entry.key);
      points[key] ??= LatLng(latitude, longitude);
    }

    return [
      for (final key in groups.keys)
        _Place(point: points[key]!, items: groups[key]!),
    ];
  }
}

/// One spot on the map and the photos taken there.

class _Place {
  const _Place({required this.point, required this.items});

  final LatLng point;
  final List<MediaItem> items;
}

class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker({required this.place, required this.onTap});

  final _Place place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: place.items.length == 1
            ? place.items.first.name
            : '${place.items.length} photos',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(blurRadius: 4, color: Colors.black38),
                ],
              ),
              child: ClipOval(
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: MediaThumbnail(item: place.items.first),
                  ),
                ),
              ),
            ),
            if (place.items.length > 1)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: Text(
                    '${place.items.length}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The photos taken at one spot, offered as thumbnails to choose from.

class _PlaceDialog extends StatelessWidget {
  const _PlaceDialog({required this.place});

  final _Place place;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${place.items.length} photos taken here'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in place.items)
              Tooltip(
                message: item.name,
                child: InkWell(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await showPreviewDialog(context, item);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: MediaThumbnail(item: item),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer),
          ),
        ),
      ),
    );
  }
}
