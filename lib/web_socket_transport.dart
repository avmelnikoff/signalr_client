import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'errors.dart';
import 'http_connection_options.dart';
import 'ihub_protocol.dart';
import 'itransport.dart';
import 'utils.dart';

class WebSocketTransport implements ITransport {
  // Properties

  Logger? _logger;
  // AccessTokenFactory? _accessTokenFactory;
  HttpConnectionOptions _options;
  bool _logMessageContent;
  WebSocketChannel? _webSocket;
  StreamSubscription<Object?>? _webSocketListenSub;

  @override
  OnClose? onClose;

  @override
  OnReceive? onReceive;

  // Methods
  WebSocketTransport(
    // AccessTokenFactory? accessTokenFactory,
    this._options,
    Logger? logger,
    bool logMessageContent,
  )   : // this._accessTokenFactory = accessTokenFactory,
        this._logger = logger,
        this._logMessageContent = logMessageContent;

  @override
  Future<void> connect(String? url, TransferFormat transferFormat) async {
    assert(url != null);

    _logger?.finest("(WebSockets transport) Connecting");

    if (_options.accessTokenFactory != null) {
      final token = await _options.accessTokenFactory!();
      if (!isStringEmpty(token)) {
        final encodedToken = Uri.encodeComponent(token);
        url = url! +
            (url.indexOf("?") < 0 ? "?" : "&") +
            "access_token=$encodedToken";
      }
    }

    var websocketCompleter = Completer();
    var opened = false;
    url = url!.replaceFirst('http', 'ws');
    
    MessageHeaders headers = MessageHeaders();
    headers.addMessageHeaders(_options.headers);

    if (_options.cookies != null) {
      final cookieHeader = headers.getHeaderValue(HttpHeaders.cookieHeader);
      final newCookieHeader =
          await _options.cookies!.getCookieHeader(url, cookieHeader);
      if (newCookieHeader?.isNotEmpty ?? false) {
        headers.setHeaderValue(HttpHeaders.cookieHeader, newCookieHeader!);
      }
    }

    _logger?.finest("WebSocket try connecting to '$url'.");
    _logger?.finest("WebSocket connect headers ${headers.asMap}");

    // _webSocket = WebSocketChannel.connect(Uri.parse(url));
    _webSocket =
        IOWebSocketChannel.connect(Uri.parse(url), headers: headers.asMap);

    opened = true;
    if (!websocketCompleter.isCompleted) websocketCompleter.complete();
    _logger?.info("WebSocket connected to '$url'.");
    _webSocketListenSub = _webSocket!.stream.listen(
      // onData
      (Object? message) {
        if (_logMessageContent && message is String) {
          _logger?.finest(
              "(WebSockets transport) data received. message ${getDataDetail(message, _logMessageContent)}.");
        } else {
          _logger?.finest("(WebSockets transport) data received.");
        }
        if (onReceive != null) {
          try {
            onReceive!(message);
          } catch (error) {
            _logger?.severe(
                "(WebSockets transport) error calling onReceive, error: $error");
            _close();
          }
        }
      },

      // onError
      onError: (Object? error) {
        var e = error != null ? error : "Unknown websocket error";
        if (!websocketCompleter.isCompleted) {
          websocketCompleter.completeError(e);
        }
      },

      // onDone
      onDone: () {
        // Don't call close handler if connection was never established
        // We'll reject the connect call instead
        if (opened) {
          if (onClose != null) {
            onClose!();
          }
        } else {
          if (!websocketCompleter.isCompleted) {
            websocketCompleter
                .completeError("There was an error with the transport.");
          }
        }
      },
    );

    return websocketCompleter.future;
  }

  @override
  Future<void> send(Object data) {
    if (_webSocket != null) {
      _logger?.finest(
          "(WebSockets transport) sending data. ${getDataDetail(data, true)}.");
      //_logger?.finest("(WebSockets transport) sending data.");

      if (data is String) {
        _webSocket!.sink.add(data);
      } else if (data is Uint8List) {
        _webSocket!.sink.add(data);
      } else {
        throw GeneralError("Content type is not handled.");
      }

      return Future.value(null);
    }

    return Future.error(GeneralError("WebSocket is not in the OPEN state"));
  }

  @override
  Future<void> stop() async {
    await _close();
    return Future.value(null);
  }

  _close() async {
    if (_webSocket != null) {
      // Clear websocket handlers because we are considering the socket closed now
      await _webSocketListenSub?.cancel();
      _webSocketListenSub = null;

      _webSocket!.sink.close();
      _webSocket = null;
    }

    _logger?.finest("(WebSockets transport) socket closed.");
    if (onClose != null) {
      onClose!();
    }
  }
}
