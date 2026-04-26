import 'dart:math';

import 'package:camera/camera.dart';

class MotionComputationResult {
  const MotionComputationResult({required this.motionScore, required this.currentRoi});

  final double motionScore;
  final List<int> currentRoi;
}

class MotionMath {
  static MotionComputationResult computeCenterLumaScore({
    required CameraImage image,
    required List<int>? previousRoi,
    double roiRatio = 0.03,
  }) {
    final plane = image.planes.first;
    final width = image.width;
    final height = image.height;
    final roiWidth = max(1, (width * roiRatio).round());
    final roiHeight = max(1, (height * roiRatio).round());
    final startX = (width - roiWidth) ~/ 2;
    final startY = (height - roiHeight) ~/ 2;

    final bytes = plane.bytes;
    final bytesPerRow = plane.bytesPerRow;
    final bytesPerPixel = plane.bytesPerPixel ?? 1;

    final roi = List<int>.filled(roiWidth * roiHeight, 0, growable: false);
    var index = 0;
    for (var y = startY; y < startY + roiHeight; y++) {
      final rowOffset = y * bytesPerRow;
      for (var x = startX; x < startX + roiWidth; x++) {
        final pixelOffset = rowOffset + (x * bytesPerPixel);
        roi[index++] = bytes[pixelOffset];
      }
    }

    if (previousRoi == null || previousRoi.length != roi.length) {
      return MotionComputationResult(motionScore: 0, currentRoi: roi);
    }

    var absDiffSum = 0;
    for (var i = 0; i < roi.length; i++) {
      absDiffSum += (roi[i] - previousRoi[i]).abs();
    }

    final maxDiff = roi.length * 255;
    final score = maxDiff == 0 ? 0.0 : absDiffSum / maxDiff;

    return MotionComputationResult(motionScore: score, currentRoi: roi);
  }
}
