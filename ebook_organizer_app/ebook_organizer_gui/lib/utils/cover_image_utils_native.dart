import 'dart:io';
import 'package:flutter/material.dart';

/// Native implementation — uses dart:io File for local cover images
Widget buildCoverImage({
  required String coverPath,
  required BoxFit fit,
  double? width,
  double? height,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) {
  return Image.file(
    File(coverPath),
    fit: fit,
    width: width,
    height: height,
    errorBuilder: errorBuilder,
  );
}
