/// The route the preview opens in, growing out of the tile that was opened.
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

import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The preview's route: an ordinary dialogue route whose opening transition
/// grows the dialogue from [origin], the rectangle of the tile that was
/// opened, to its full size. Without an origin it opens as any dialogue does.

class PreviewRoute extends DialogRoute<void> {
  PreviewRoute({
    required super.context,
    required super.builder,
    required this.origin,
    required this.contentKey,
    super.themes,
    super.barrierColor,
  });

  final Rect? origin;

  /// Marks the dialogue's panel, whose laid out rectangle is where the
  /// growth ends.

  final GlobalKey contentKey;

  static const _grow = Duration(milliseconds: 300);

  @override
  Duration get transitionDuration =>
      origin == null ? super.transitionDuration : _grow;

  @override
  Duration get reverseTransitionDuration =>
      origin == null ? super.reverseTransitionDuration : _fadeOut;

  static const _fadeOut = Duration(milliseconds: 150);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final origin = this.origin;
    if (origin == null) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }

    // The same widgets are built while opening and closing, so that the
    // dialogue keeps its state. Closing only fades: by then the user may
    // have stepped to a file whose tile is elsewhere, or off screen.

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final closing = animation.status == AnimationStatus.reverse;
        final value = animation.value;
        return _GrowFrom(
          origin: origin,
          target: contentKey,
          progress: closing ? 1 : Curves.easeOutCubic.transform(value),
          child: Opacity(
            opacity: closing ? value : const Interval(0, 0.35).transform(value),
            child: child,
          ),
        );
      },
    );
  }
}

/// Paints its child scaled and moved so that the panel marked by [target]
/// starts within [origin] and, as [progress] runs from 0 to 1, grows to
/// where it was laid out.
///
/// The panel keeps its own shape throughout, starting as large as fits in
/// the tile, so the photo and the header are never stretched. Layout is
/// untouched: only painting is transformed.

class _GrowFrom extends SingleChildRenderObjectWidget {
  const _GrowFrom({
    required this.origin,
    required this.target,
    required this.progress,
    super.child,
  });

  /// Where the growth starts, in global coordinates.

  final Rect origin;

  final GlobalKey target;

  final double progress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGrowFrom(origin: origin, target: target, progress: progress);

  @override
  void updateRenderObject(BuildContext context, _RenderGrowFrom renderObject) {
    renderObject
      ..origin = origin
      ..target = target
      ..progress = progress;
  }
}

class _RenderGrowFrom extends RenderProxyBox {
  _RenderGrowFrom({
    required Rect origin,
    required GlobalKey target,
    required double progress,
  }) : _origin = origin,
       _target = target,
       _progress = progress;

  Rect _origin;
  set origin(Rect value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  GlobalKey _target;
  set target(GlobalKey value) {
    if (value == _target) return;
    _target = value;
    markNeedsPaint();
  }

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsPaint();
  }

  // The panel is found when painting, after it has been laid out, so the
  // growth always ends exactly where the dialogue sits.

  Matrix4? _transform() {
    if (_progress >= 1) return null;
    final box = _target.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;

    final end = MatrixUtils.transformRect(
      box.getTransformTo(this),
      Offset.zero & box.size,
    );
    final start = globalToLocal(_origin.topLeft) & _origin.size;
    final first = min(start.width / end.width, start.height / end.height);

    final scale = lerpDouble(first, 1, _progress)!;
    final centre = Offset.lerp(start.center, end.center, _progress)!;
    return Matrix4.translationValues(centre.dx, centre.dy, 0)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
      ..multiply(Matrix4.translationValues(-end.center.dx, -end.center.dy, 0));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = _transform();
    if (transform == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }
}
