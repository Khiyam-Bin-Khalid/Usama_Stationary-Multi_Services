import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ProxyMode {
  up,
  /// Connections are refused: the network or server is gone.
  down,
  /// The server handles requests but the replies never arrive.
  dropResponses,
  /// Something answers, but only with 503 (API up, its database unreachable).
  serverError,
}

/// TCP proxy between the app's client and the real API, so a test can cut the
/// connection exactly the way a shop's network drops.
class KillSwitchProxy {
  final int port;
  final int upstreamPort;
  ProxyMode _mode = ProxyMode.up;
  ServerSocket? _server;
  final _open = <Socket>{};

  ProxyMode get mode => _mode;

  /// Also drops live connections: HTTP clients keep them open between
  /// requests, and a real outage wouldn't spare those.
  set mode(ProxyMode value) {
    _mode = value;
    for (final socket in _open.toList()) {
      socket.destroy();
    }
  }

  KillSwitchProxy({required this.port, required this.upstreamPort});

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close();
    for (final s in _open) {
      s.destroy();
    }
  }

  Future<void> _handle(Socket client) async {
    _open.add(client);
    client.done.whenComplete(() => _open.remove(client)).ignore();
    switch (mode) {
      case ProxyMode.down:
        client.destroy();
      case ProxyMode.serverError:
        client.listen((_) {
          client.add(utf8.encode('HTTP/1.1 503 Service Unavailable\r\ncontent-length: 0\r\nconnection: close\r\n\r\n'));
          client.flush().whenComplete(client.destroy);
        }, onError: (_) {});
      case ProxyMode.up:
      case ProxyMode.dropResponses:
        final drop = mode == ProxyMode.dropResponses;
        final upstream = await Socket.connect(InternetAddress.loopbackIPv4, upstreamPort);
        _open.add(upstream);
        client.listen(upstream.add, onDone: upstream.destroy, onError: (_) => upstream.destroy());
        upstream.listen(
          (data) {
            if (drop) {
              client.destroy();
            } else {
              client.add(data);
            }
          },
          onDone: client.destroy,
          onError: (_) => client.destroy(),
        );
    }
  }
}
