library go_pts_client;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';

class RealtimeMessageTypes {
  static const String realtimeMessageTypeSubscribe = "subscribe";
  static const String realtimeMessageTypeUnsubscribe = "unsubscribe";
  static const String realtimeMessageTypeChannelMessage = "message";
}

class GoPTSClientConfig {
  final Duration retryDelay;
  final Uri uri;

  GoPTSClientConfig({this.retryDelay = const Duration(seconds: 5), required this.uri});
}

class IncommingMessage {
  late final String channel;
  late final dynamic payload;

  IncommingMessage.parse(dynamic json) {
    final parsed = jsonDecode(json);
    channel = parsed['channel'];
    payload = parsed['payload'];
  }
}

class GoPTSClient {
  final GoPTSClientConfig config;
  final Map<String, List<StreamController<dynamic>>> _handler = {};
  IOWebSocketChannel? _socket;
  StreamSubscription<dynamic>? _socketSub;
  bool _disposed = false;

  GoPTSClient(this.config);

  Future<void> connect() async {
    if (_socket != null) {
      return;
    }
    
    _socket = IOWebSocketChannel.connect(config.uri);

    _socketSub = _socket!.stream.listen((message) {
      final parsed = IncommingMessage.parse(message);
      _handleMessage(parsed);
    });

    _socketSub?.onDone(() async {
      _socketSub = null;
      await Future.delayed(config.retryDelay);
      if (_disposed) return;
      connect();
    });
  }

  void dispose() {
    _disposed = true;
    if (_socketSub != null) {
      _socketSub!.cancel();
    }
  }

  void _handleMessage(IncommingMessage message) {
    final channelHandler = _handler[message.channel];
    if (channelHandler != null) {
      for (final streamController in channelHandler) {
        streamController.add(message.payload);
      }
    }
  }

  void send(String channel, { dynamic payload = const <String, dynamic>{}, String type = RealtimeMessageTypes.realtimeMessageTypeChannelMessage }) {
    _socket?.sink.add(jsonEncode({
      "type": type,
      "channel": channel,
      "payload": payload,
    }));
  }

  Stream<dynamic> subscribeChannel(String channel) {
    StreamController streamController = StreamController<dynamic>();

    streamController.onCancel = () {
      unregisterHandler(channel, streamController);
    };
    registerHandler(channel, streamController);

    send(channel, type: RealtimeMessageTypes.realtimeMessageTypeSubscribe);

    return streamController.stream;
  }

  void registerHandler(String channel, StreamController<dynamic> handler) {
    _handler.putIfAbsent(channel, () => []);
    _handler[channel]!.add(handler);
  }

  void unregisterHandler(String channel, StreamController<dynamic> handler) {
    final channelHandler = _handler[channel];
    if (channelHandler != null) {
      if (!handler.isClosed) {
        handler.close();
      }
      
      channelHandler.remove(handler);

      if (channelHandler.isEmpty) {
        _handler.remove(channel);
        send(channel, type: RealtimeMessageTypes.realtimeMessageTypeUnsubscribe);
      }
    }
  }

}