import 'map_worker_transport.dart';

/// Außerhalb des Browsers gibt es keinen Web Worker.
MapWorkerTransport? createWebWorkerTransport() => null;
