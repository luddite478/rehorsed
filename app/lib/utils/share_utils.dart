import 'package:flutter/material.dart';

Rect getSharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox && renderObject.hasSize) {
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  // iOS/iPad share sheets require a source rect; use a safe fallback.
  return const Rect.fromLTWH(0, 0, 100, 100);
}
