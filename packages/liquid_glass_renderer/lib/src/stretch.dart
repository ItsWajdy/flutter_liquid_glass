import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/glass_drag_builder.dart';
import 'package:meta/meta.dart';
import 'package:motor/motor.dart';

/// A widget that provides a squash and stretch effect to its child based on
/// user interaction.
///
/// Will listen to drag gestures from the user without interfering with other
/// gestures.
class LiquidStretch extends StatelessWidget {
  /// Creates a new [LiquidStretch] widget with the given [child],
  /// [interactionScale], and [stretch].
  const LiquidStretch({
    required this.child,
    this.interactionScale = 1.05,
    this.stretch = .5,
    super.key,
  });

  /// The scale factor to apply when the user is interacting with the widget.
  ///
  /// A value of 1.0 means no scaling.
  /// A value greater than 1.0 means the widget will scale up.
  /// A value less than 1.0 means the widget will scale down.
  ///
  /// Defaults to 1.05.
  final double interactionScale;

  /// The factor to multiply the drag offset by to determine the stretch
  /// amount in pixels.
  ///
  /// A value of 0.0 means no stretch.
  ///
  /// Defaults to 0.5.
  final double stretch;

  /// The child widget to apply the stretch effect to.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (stretch == 0 && interactionScale == 1.0) {
      return child;
    }

    return GlassDragBuilder(
      builder: (context, value, child) {
        final scale = value == null ? 1.0 : interactionScale;
        return SingleMotionBuilder(
          value: scale,
          motion: const Motion.smoothSpring(
            duration: Duration(milliseconds: 300),
            snapToEnd: true,
          ),
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: child,
          ),
          child: MotionBuilder(
            value: value?.withResistance(.08) ?? Offset.zero,
            motion: value == null
                ? const Motion.bouncySpring(snapToEnd: true)
                : const Motion.interactiveSpring(snapToEnd: true),
            converter: const OffsetMotionConverter(),
            builder: (context, value, child) => _RawGlassStretch(
              stretchPixels: value * stretch,
              child: child!,
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// {@template raw_liquid_stretch}
/// Use this widget to apply a custom stretch effect in pixels to its child.
///
/// You can control the stretch effect by providing an [Offset] in pixels
/// via the [stretchPixels] property.
///
/// If you simply want to apply a stretch effect based on user drag gestures,
/// consider using [LiquidStretch] instead, which provides built-in drag
/// handling and resistance.
/// {@endtemplate}
class RawLiquidStretch extends SingleChildRenderObjectWidget {
  /// {@macro raw_liquid_stretch}
  const RawLiquidStretch({
    required this.stretchPixels,
    required super.child,
    super.key,
  });

  /// The stretch offset in pixels.
  final Offset stretchPixels;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderGlassStretch(stretchPixels: stretchPixels);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlassStretch renderObject,
  ) {
    renderObject.stretchPixels = stretchPixels;
  }
}

class _RenderGlassStretch extends RenderProxyBox {
  _RenderGlassStretch({
    required Offset stretchPixels,
  }) : _stretchPixels = stretchPixels;

  Offset _stretchPixels;

  /// The stretch offset in pixels.
  Offset get stretchPixels => _stretchPixels;
  set stretchPixels(Offset value) {
    if (_stretchPixels == value) {
      return;
    }
    _stretchPixels = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    return hitTestChildren(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final Matrix4? transform = _getEffectiveTransform();
    if (transform == null) {
      return super.hitTestChildren(result, position: position);
    }

    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) {
        return super.hitTestChildren(result, position: position);
      },
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }

    final Matrix4? transform = _getEffectiveTransform();
    if (transform == null) {
      super.paint(context, offset);
      return;
    }

    // Check if the matrix is singular
    final double det = transform.determinant();
    if (det == 0 || !det.isFinite) {
      layer = null;
      return;
    }

    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final Matrix4? effectiveTransform = _getEffectiveTransform();
    if (effectiveTransform != null) {
      transform.multiply(effectiveTransform);
    }
  }

  Matrix4? _getEffectiveTransform() {
    if (_stretchPixels == Offset.zero || !size.isEmpty) {
      if (_stretchPixels == Offset.zero) {
        return null;
      }
    }

    final scale = getScale(
      stretchPixels: _stretchPixels,
      size: size,
    );

    final matrix = Matrix4.identity()
      ..scaleByDouble(scale.dx, scale.dy, 1, 1)
      ..translateByDouble(_stretchPixels.dx, _stretchPixels.dy, 0, 1);

    return matrix;
  }

  @internal
  Offset getScale({
    required Offset stretchPixels,
    required Size size,
  }) {
    if (size.isEmpty) {
      return const Offset(1.0, 1.0);
    }

    final stretchX = stretchPixels.dx.abs();
    final stretchY = stretchPixels.dy.abs();

    // Convert pixel stretch to relative stretch based on size
    final relativeStretchX = size.width > 0 ? stretchX / size.width : 0.0;
    final relativeStretchY = size.height > 0 ? stretchY / size.height : 0.0;

    // Use a consistent stretch factor for both dimensions
    const stretchFactor = 1.0;
    const volumeFactor = 0.5;

    final baseScaleX = 1 + relativeStretchX * stretchFactor;
    final baseScaleY = 1 + relativeStretchY * stretchFactor;

    // Calculate magnitude in relative space for volume preservation
    final magnitude = math.sqrt(
      relativeStretchX * relativeStretchX + relativeStretchY * relativeStretchY,
    );
    final targetVolume = 1 + magnitude * volumeFactor;
    final currentVolume = baseScaleX * baseScaleY;
    final volumeCorrection = math.sqrt(targetVolume / currentVolume);

    final finalScaleX = baseScaleX * volumeCorrection;
    final finalScaleY = baseScaleY * volumeCorrection;

    return Offset(finalScaleX, finalScaleY);
  }
}

extension on Offset {
  Offset withResistance(double resistance) {
    if (resistance == 0) return this;

    final magnitude = math.sqrt(dx * dx + dy * dy);
    if (magnitude == 0) return Offset.zero;

    final resistedMagnitude = magnitude / (1 + magnitude * resistance);
    final scale = resistedMagnitude / magnitude;

    return Offset(dx * scale, dy * scale);
  }
}
