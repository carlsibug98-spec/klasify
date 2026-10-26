import 'package:flutter/material.dart';

/// Neutral loading placeholder for lists and dashboard cards.
class KlasifySkeleton extends StatelessWidget {
  const KlasifySkeleton({
    super.key,
    this.height = 18,
    this.width = double.infinity,
    this.radius = 10,
  });

  final double height;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}
