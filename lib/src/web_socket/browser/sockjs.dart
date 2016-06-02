// Copyright 2015 Workiva Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

library w_transport.src.web_socket.browser.sockjs;

import 'dart:async';

import 'package:sockjs_client/sockjs_client.dart' as sockjs;

import 'package:w_transport/src/web_socket/common/w_socket.dart';
import 'package:w_transport/src/web_socket/w_socket.dart';
import 'package:w_transport/src/web_socket/w_socket_exception.dart';

class SockJSSocket extends CommonWSocket implements WSocket {
  static Future<WSocket> connect(Uri uri,
      {bool debug: false,
      bool noCredentials: false,
      List<String> protocolsWhitelist,
      Duration timeout}) async {
    if (uri.scheme == 'ws') {
      uri = uri.replace(scheme: 'http');
    } else if (uri.scheme == 'wss') {
      uri = uri.replace(scheme: 'https');
    }

    sockjs.Client client = new sockjs.Client(uri.toString(),
        debug: debug == true,
        noCredentials: noCredentials == true,
        protocolsWhitelist: protocolsWhitelist,
        timeout: timeout != null ? timeout.inMilliseconds : null);

    // Listen for and store the close event. This will determine whether or
    // not the socket connected successfully, and will also be used later
    // to handle the web socket closing.
    var closed = client.onClose.first;

    // Will complete if the socket successfully opens, or complete with
    // an error if the socket moves straight to the closed state.
    Completer connected = new Completer();
    client.onOpen.first.then(connected.complete);
    closed.then((_) {
      if (!connected.isCompleted) {
        connected
            .completeError(new WSocketException('Could not connect to $uri'));
      }
    });

    await connected.future;
    return new SockJSSocket._(client, closed);
  }

  sockjs.Client _webSocket;

  SockJSSocket._(this._webSocket, Future webSocketClosed) : super() {
    webSocketClosed.then((closeEvent) {
      closeCode = closeEvent.code;
      closeReason = closeEvent.reason;
      onIncomingDone();
    });

    // Note: We don't listen to the SockJS client for messages immediately like
    // we do with the native WebSockets. This is because the event streams from
    // the SockJS client are all drawn from a single broadcast stream. To make
    // it act like a single subscription stream (and thus make it fit the
    // interface of a standard Stream), we create a subscription when a consumer
    // listens to this WSocket instance, cancel that subscription when the
    // consumer's subscription is paused, and re-listen when the consumer
    // resumes listening. See [onIncomingListen], [onIncomingPause], and
    // [onIncomingResume].

    // Additional note: the SockJS Client has no error stream, so no need to
    // listen to for errors.
  }

  @override
  void closeWebSocket(int code, String reason) {
    _webSocket.close(code, reason);
  }

  @override
  void onIncomingError(error, [StackTrace stackTrace]) {
    shutDown(error: error, stackTrace: stackTrace);
  }

  @override
  void onIncomingListen() {
    // When this [WSocket] instance is listened to, start listening to the
    // SockJS client's broadcast stream.
    webSocketSubscription = _webSocket.onMessage.listen((messageEvent) {
      onIncomingData(messageEvent.data);
    });
  }

  @override
  void onIncomingPause() {
    // When this [WSocket]'s subscription is paused, cancel the subscription to
    // the SockJS client's broadcast stream. This is the recommended behavior
    // when proxying a subscription to a broadcast stream. This effectively
    // prevents buffering events indefinitely (a possible memory leak) by
    // canceling the subscription altogether. When the subscription to this
    // [WSocket] instance is resumed, we will re-subscribe.
    webSocketSubscription.cancel();
  }

  @override
  void onIncomingResume() {
    // Resubscribe to the SockJS client's broadcast stream to effectively resume
    // the consumer's subscription to this [WSocket] instance.
    webSocketSubscription = _webSocket.onMessage.listen((messageEvent) {
      onIncomingData(messageEvent.data);
    });
  }

  @override
  void onOutgoingData(data) {
    // Pipe messages through to the underlying socket.
    _webSocket.send(data);
  }

  @override
  void validateOutgoingData(Object data) {
    if (data is! String) {
      throw new ArgumentError(
          'WSocket data type must be a String when using SockJS.');
    }
  }
}
