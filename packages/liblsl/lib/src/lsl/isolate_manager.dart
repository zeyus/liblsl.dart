import 'dart:async';
import 'dart:isolate';
import 'dart:ffi' show NativeType;
import 'dart:math' show Random;

import 'package:liblsl/src/lsl/isolated_inlet.dart';
import 'package:liblsl/src/lsl/isolated_outlet.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';

/// Message types for communication between isolates
enum LSLMessageType {
  createOutlet,
  createInlet,
  pushChunk,
  pushSample,
  pullChunk,
  pullSample,
  waitForConsumer,
  destroy,
  resolveStreams,
  samplesAvailable,
  flush,
  timeCorrection,
}

/// A message payload for communication between isolates
class LSLMessage {
  final String id;
  final LSLMessageType type;
  final Map<String, dynamic> data;

  LSLMessage(this.type, this.data, {String? id})
    : id = id ?? _generateMessageId();

  static String _generateMessageId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'type': type.index, 'data': data};
  }

  factory LSLMessage.fromMap(Map<String, dynamic> map) {
    return LSLMessage(
      LSLMessageType.values[map['type'] as int],
      map['data'] as Map<String, dynamic>,
      id: map['id'] as String,
    );
  }
}

/// A response message from an isolate
class LSLResponse {
  final String messageId;
  final bool success;
  final dynamic result;
  final String? error;

  LSLResponse({
    required this.messageId,
    required this.success,
    this.result,
    this.error,
  });

  factory LSLResponse.success(String messageId, dynamic result) {
    return LSLResponse(messageId: messageId, success: true, result: result);
  }

  factory LSLResponse.error(String messageId, String message) {
    return LSLResponse(messageId: messageId, success: false, error: message);
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'success': success,
      'result': result,
      'error': error,
    };
  }

  factory LSLResponse.fromMap(Map<String, dynamic> map) {
    return LSLResponse(
      messageId: map['messageId'] as String,
      success: map['success'] as bool,
      result: map['result'],
      error: map['error'] as String?,
    );
  }
}

/// Handles serialization of complex types between isolates
class LSLSerializer {
  /// Serialize stream info to pass between isolates
  static Map<String, dynamic> serializeStreamInfo(LSLStreamInfo info) {
    return {
      'streamName': info.streamName,
      'streamType': info.streamType.value,
      'channelCount': info.channelCount,
      'sampleRate': info.sampleRate,
      'channelFormat': info.channelFormat.index,
      'sourceId': info.sourceId,
      'address': info.streamInfo.address,
    };
  }

  /// Serialize a sample for passing between isolates
  static Map<String, dynamic> serializeSample<T>(LSLSample<T> sample) {
    return {
      'data': sample.data,
      'timestamp': sample.timestamp,
      'errorCode': sample.errorCode,
    };
  }

  /// Deserialize a sample
  static LSLSample<T> deserializeSample<T>(Map<String, dynamic> map) {
    return LSLSample<T>(
      List<T>.from(map['data'] as List),
      map['timestamp'] as double,
      map['errorCode'] as int,
    );
  }

  /// Serialize LSLSamplePointer`<`T`>` (T extends NativeType).
  static Map<String, dynamic> serializeSamplePointer<T extends NativeType>(
    LSLSamplePointer<T> sample,
  ) {
    return {
      'timestamp': sample.timestamp,
      'errorCode': sample.errorCode,
      'pointerAddress': sample.pointerAddress,
    };
  }

  /// Deserialize LSLSamplePointer`<`T`>` (T extends NativeType).
  static LSLSamplePointer<T> deserializeSamplePointer<T extends NativeType>(
    Map<String, dynamic> map,
  ) {
    return LSLSamplePointer<T>(
      map['timestamp'] as double,
      map['errorCode'] as int,
      map['pointerAddress'] as int,
    );
  }
}

/// Base class for isolate managers
abstract class LSLIsolateManagerBase {
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _sendPort;
  final Completer<void> _initialization = Completer<void>();
  Isolate? _isolate;

  /// Map to track pending requests
  final Map<String, Completer<LSLResponse>> _pendingRequests = {};

  LSLIsolateManagerBase() {
    _listen();
  }

  void _listen() {
    _receivePort.listen((message) {
      if (message is SendPort) {
        // Initial handshake from isolate
        _sendPort = message;
        if (!_initialization.isCompleted) {
          _initialization.complete();
        }
      } else if (message is Map<String, dynamic>) {
        // Response from isolate
        final response = LSLResponse.fromMap(message);
        final completer = _pendingRequests.remove(response.messageId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(response);
        }
      }
    });
  }

  /// Initialize the isolate
  Future<void> init() async {
    if (_initialization.isCompleted) return;

    _isolate = await Isolate.spawn(
      getIsolateEntryPoint(),
      _receivePort.sendPort,
    );
    return _initialization.future;
  }

  /// Get the isolate entry point function - to be implemented by subclasses
  void Function(Object) getIsolateEntryPoint();

  /// Send a message to the isolate
  Future<LSLResponse> sendMessage(LSLMessage message) async {
    if (!_initialization.isCompleted) {
      await init();
    }

    if (_sendPort == null) {
      throw StateError('Isolate communication not established');
    }

    final completer = Completer<LSLResponse>();
    _pendingRequests[message.id] = completer;

    // Add timeout to prevent hanging forever
    Timer(Duration(seconds: 30), () {
      final pendingCompleter = _pendingRequests.remove(message.id);
      if (pendingCompleter != null && !pendingCompleter.isCompleted) {
        pendingCompleter.complete(
          LSLResponse.error(message.id, 'Request timeout'),
        );
      }
    });

    _sendPort!.send(message.toMap());
    return completer.future;
  }

  /// Clean up resources
  void dispose() {
    // Complete any pending requests with errors
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(LSLResponse.error('', 'Isolate disposed'));
      }
    }
    _pendingRequests.clear();

    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
  }
}

/// Manages communication with outlet isolates
class LSLOutletIsolateManager extends LSLIsolateManagerBase {
  @override
  void Function(Object) getIsolateEntryPoint() => _outletIsolateEntryPoint;

  /// Entry point for the outlet isolate
  static void _outletIsolateEntryPoint(Object mainSendPort) {
    if (mainSendPort is SendPort) {
      // If we receive a SendPort directly, we can use it
      LSLOutletIsolate(mainSendPort);
    } else {
      throw ArgumentError('Expected SendPort');
    }
  }
}

/// Manages communication with inlet isolates
class LSLInletIsolateManager extends LSLIsolateManagerBase {
  @override
  void Function(Object) getIsolateEntryPoint() => _inletIsolateEntryPoint;

  /// Entry point for the inlet isolate
  static void _inletIsolateEntryPoint(Object mainSendPort) {
    if (mainSendPort is SendPort) {
      // If we receive a SendPort directly, we can use it
      LSLInletIsolate(mainSendPort);
    } else {
      throw ArgumentError('Expected SendPort');
    }
  }
}

/// Base class for isolate workers
abstract class LSLIsolateWorkerBase {
  final ReceivePort receivePort = ReceivePort();
  final SendPort sendPort;

  LSLIsolateWorkerBase(this.sendPort) {
    _listen();

    // Send our receive port to establish bidirectional communication
    sendPort.send(receivePort.sendPort);
  }

  void _listen() {
    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        _handleMessage(message);
      }
    });
  }

  void _handleMessage(Map<String, dynamic> messageMap) async {
    try {
      final message = LSLMessage.fromMap(messageMap);
      final result = await handleMessage(message);

      sendPort.send(LSLResponse.success(message.id, result).toMap());
    } catch (e) {
      final messageId = messageMap['id'] as String? ?? '';
      sendPort.send(LSLResponse.error(messageId, e.toString()).toMap());
    }
  }

  /// Handle a message - to be implemented by subclasses
  Future<dynamic> handleMessage(LSLMessage message);

  /// Send cleanup signal and close receive port
  void cleanup() {
    receivePort.close();
  }
}
