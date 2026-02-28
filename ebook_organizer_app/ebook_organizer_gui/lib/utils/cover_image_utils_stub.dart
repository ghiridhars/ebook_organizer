import 'package:flutter/material.dart';

/// Web stub — file-based images are not supported on web
Widget buildCoverImage({
  required String coverPath,
  required BoxFit fit,
  double? width,
  double? height,
  required Widget Function(BuildContext, Object, StackTrace?) errorBuilder,
}) {
  // On web, cover paths are local filesystem paths that can't be loaded
  return Builder(builder: (context) => errorBuilder(context, 'Web platform', null));
}
