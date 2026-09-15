import 'package:flutter/material.dart';

/// Stile card post come le ricette SmartChef: tilt e angoli diversi per id.
class PostPuzzleStyle {
  final double tilt;
  final double imageAspect;
  final BorderRadius radius;

  const PostPuzzleStyle({
    required this.tilt,
    required this.imageAspect,
    required this.radius,
  });

  factory PostPuzzleStyle.forId(String id) {
    final seed = id.hashCode.abs();
    const tiltChoices = <double>[-0.028, 0.02, -0.014, 0.032, -0.022, 0.01];
    const aspectChoices = <double>[0.68, 0.82, 0.94, 1.08, 0.74, 1.22];
    const radiusChoices = <BorderRadius>[
      BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(20),
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(7),
      ),
      BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(6),
        bottomLeft: Radius.circular(10),
        bottomRight: Radius.circular(22),
      ),
      BorderRadius.only(
        topLeft: Radius.circular(12),
        topRight: Radius.circular(16),
        bottomLeft: Radius.circular(22),
        bottomRight: Radius.circular(8),
      ),
      BorderRadius.only(
        topLeft: Radius.circular(6),
        topRight: Radius.circular(14),
        bottomLeft: Radius.circular(8),
        bottomRight: Radius.circular(18),
      ),
    ];
    return PostPuzzleStyle(
      tilt: tiltChoices[seed % tiltChoices.length],
      imageAspect: aspectChoices[seed % aspectChoices.length],
      radius: radiusChoices[seed % radiusChoices.length],
    );
  }
}
