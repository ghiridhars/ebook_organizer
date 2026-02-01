import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// FFI implementation for desktop platforms (Windows/Linux)
void initializeFfi() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
