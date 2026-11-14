// The Dio adapter the app uses for its own API (connection pool tuned for many
// small parallel requests). Web keeps Dio's browser adapter.
export 'tuned_adapter_stub.dart' if (dart.library.io) 'tuned_adapter_io.dart';
