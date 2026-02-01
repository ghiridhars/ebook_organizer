// Conditional export for platform-specific backend service
export 'backend_service_stub.dart'
    if (dart.library.io) 'backend_service_native.dart';
