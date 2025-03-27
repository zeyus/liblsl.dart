import 'dart:async';
import 'dart:isolate';
import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/stream_inlet.dart';
import 'package:liblsl/src/lsl/stream_outlet.dart';
import 'package:liblsl/src/lsl/stream_resolver.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/structs.dart';

// Messages for isolate communication
class _StreamInfoMsg {
  final String streamName;
  final LSLContentType streamType;
  final int channelCount;
  final double sampleRate;
  final LSLChannelFormat channelFormat;
  final String sourceId;

  _StreamInfoMsg({
    required this.streamName,
    required this.streamType,
    required this.channelCount,
    required this.sampleRate,
    required this.channelFormat,
    required this.sourceId,
  });

  Map<String, dynamic> toMap() {
    return {
      'streamName': streamName,
      'streamType': streamType.value,
      'channelCount': channelCount,
      'sampleRate': sampleRate,
      'channelFormat': channelFormat.index,
      'sourceId': sourceId,
    };
  }

  static _StreamInfoMsg fromMap(Map<String, dynamic> map) {
    return _StreamInfoMsg(
      streamName: map['streamName'],
      streamType: LSLContentType.values.firstWhere(
        (t) => t.value == map['streamType'],
        orElse: () => LSLContentType.custom(map['streamType']),
      ),
      channelCount: map['channelCount'],
      sampleRate: map['sampleRate'],
      channelFormat: LSLChannelFormat.values[map['channelFormat']],
      sourceId: map['sourceId'],
    );
  }
}

class _OutletMsg {
  final _StreamInfoMsg streamInfo;
  final int chunkSize;
  final int maxBuffer;

  _OutletMsg({
    required this.streamInfo,
    required this.chunkSize,
    required this.maxBuffer,
  });

  Map<String, dynamic> toMap() {
    return {
      'streamInfo': streamInfo.toMap(),
      'chunkSize': chunkSize,
      'maxBuffer': maxBuffer,
    };
  }

  static _OutletMsg fromMap(Map<String, dynamic> map) {
    return _OutletMsg(
      streamInfo: _StreamInfoMsg.fromMap(map['streamInfo']),
      chunkSize: map['chunkSize'],
      maxBuffer: map['maxBuffer'],
    );
  }
}

class _InletMsg {
  final _StreamInfoMsg streamInfo;
  final int maxBufferSize;
  final int maxChunkLength;
  final bool recover;

  _InletMsg({
    required this.streamInfo,
    required this.maxBufferSize,
    required this.maxChunkLength,
    required this.recover,
  });

  Map<String, dynamic> toMap() {
    return {
      'streamInfo': streamInfo.toMap(),
      'maxBufferSize': maxBufferSize,
      'maxChunkLength': maxChunkLength,
      'recover': recover,
    };
  }

  static _InletMsg fromMap(Map<String, dynamic> map) {
    return _InletMsg(
      streamInfo: _StreamInfoMsg.fromMap(map['streamInfo']),
      maxBufferSize: map['maxBufferSize'],
      maxChunkLength: map['maxChunkLength'],
      recover: map['recover'],
    );
  }
}

class _SampleMsg {
  final List<dynamic> data;
  final String commandId;

  _SampleMsg({required this.data, required this.commandId});

  Map<String, dynamic> toMap() {
    return {'data': data, 'commandId': commandId};
  }

  static _SampleMsg fromMap(Map<String, dynamic> map) {
    return _SampleMsg(data: map['data'], commandId: map['commandId']);
  }
}

class _ResolverMsg {
  final double waitTime;
  final int maxStreams;
  final double forgetAfter;
  final bool continuous;

  _ResolverMsg({
    required this.waitTime,
    required this.maxStreams,
    required this.forgetAfter,
    required this.continuous,
  });

  Map<String, dynamic> toMap() {
    return {
      'waitTime': waitTime,
      'maxStreams': maxStreams,
      'forgetAfter': forgetAfter,
      'continuous': continuous,
    };
  }

  static _ResolverMsg fromMap(Map<String, dynamic> map) {
    return _ResolverMsg(
      waitTime: map['waitTime'],
      maxStreams: map['maxStreams'],
      forgetAfter: map['forgetAfter'],
      continuous: map['continuous'],
    );
  }
}

// Main LSL API class with transparent threading
class LSL {
  // Map to store references to running isolates for cleanup
  final Map<String, Isolate> _isolates = {};
  final Map<String, SendPort> _sendPorts = {};
  final Map<String, StreamController> _controllerMap = {};

  // Isolate entry points
  static void _outletWorker(Map<String, dynamic> message) async {
    final msg = _OutletMsg.fromMap(message['config']);
    final sendPort = message['sendPort'] as SendPort;
    final receivePort = ReceivePort();

    sendPort.send({'port': receivePort.sendPort, 'status': 'ready'});

    // Create the actual outlet
    final lsl = LSL._internal();
    final streamInfo = LSLStreamInfo(
      streamName: msg.streamInfo.streamName,
      streamType: msg.streamInfo.streamType,
      channelCount: msg.streamInfo.channelCount,
      sampleRate: msg.streamInfo.sampleRate,
      channelFormat: msg.streamInfo.channelFormat,
      sourceId: msg.streamInfo.sourceId,
    );
    streamInfo.create();

    final outlet = LSLStreamOutlet(
      streamInfo: streamInfo,
      chunkSize: msg.chunkSize,
      maxBuffer: msg.maxBuffer,
    );
    outlet.create();

    // Handle messages
    await for (final data in receivePort) {
      if (data == 'destroy') {
        outlet.destroy();
        lsl.destroy();
        Isolate.exit();
      } else if (data is Map<String, dynamic>) {
        if (data['command'] == 'push') {
          final sampleMsg = _SampleMsg.fromMap(data);
          try {
            final result = await outlet.pushSample(sampleMsg.data);
            sendPort.send({
              'status': 'success',
              'commandId': sampleMsg.commandId,
              'result': result,
            });
          } catch (e) {
            sendPort.send({
              'status': 'error',
              'commandId': sampleMsg.commandId,
              'error': e.toString(),
            });
          }
        } else if (data['command'] == 'waitForConsumer') {
          final timeout = data['timeout'] as double;
          final commandId = data['commandId'] as String;
          try {
            await outlet.waitForConsumer(timeout: timeout);
            sendPort.send({'status': 'success', 'commandId': commandId});
          } catch (e) {
            sendPort.send({
              'status': 'error',
              'commandId': commandId,
              'error': e.toString(),
            });
          }
        }
      }
    }
  }

  static void _inletWorker(Map<String, dynamic> message) async {
    final msg = _InletMsg.fromMap(message['config']);
    final sendPort = message['sendPort'] as SendPort;
    final receivePort = ReceivePort();

    sendPort.send({'port': receivePort.sendPort, 'status': 'ready'});

    // Create the actual inlet
    final lsl = LSL._internal();
    final streamInfo = LSLStreamInfo(
      streamName: msg.streamInfo.streamName,
      streamType: msg.streamInfo.streamType,
      channelCount: msg.streamInfo.channelCount,
      sampleRate: msg.streamInfo.sampleRate,
      channelFormat: msg.streamInfo.channelFormat,
      sourceId: msg.streamInfo.sourceId,
    );
    streamInfo.create();

    LSLStreamInlet inlet;
    switch (streamInfo.channelFormat.dartType) {
      case const (double):
        inlet = LSLStreamInlet<double>(
          streamInfo,
          maxBufferSize: msg.maxBufferSize,
          maxChunkLength: msg.maxChunkLength,
          recover: msg.recover,
        );
        break;
      case const (int):
        inlet = LSLStreamInlet<int>(
          streamInfo,
          maxBufferSize: msg.maxBufferSize,
          maxChunkLength: msg.maxChunkLength,
          recover: msg.recover,
        );
        break;
      case const (String):
        inlet = LSLStreamInlet<String>(
          streamInfo,
          maxBufferSize: msg.maxBufferSize,
          maxChunkLength: msg.maxChunkLength,
          recover: msg.recover,
        );
        break;
      default:
        sendPort.send({'status': 'error', 'error': 'Invalid channel format'});
        Isolate.exit();
    }

    inlet.create();

    // Handle messages
    await for (final data in receivePort) {
      if (data == 'destroy') {
        inlet.destroy();
        lsl.destroy();
        Isolate.exit();
      } else if (data is Map<String, dynamic>) {
        if (data['command'] == 'pullSample') {
          final timeout = data['timeout'] as double;
          final commandId = data['commandId'] as String;
          try {
            final sample = await inlet.pullSample(timeout: timeout);
            sendPort.send({
              'status': 'success',
              'commandId': commandId,
              'data': sample.data,
              'timestamp': sample.timestamp,
              'errorCode': sample.errorCode,
            });
          } catch (e) {
            sendPort.send({
              'status': 'error',
              'commandId': commandId,
              'error': e.toString(),
            });
          }
        } else if (data['command'] == 'flush') {
          final commandId = data['commandId'] as String;
          try {
            final result = inlet.flush();
            sendPort.send({
              'status': 'success',
              'commandId': commandId,
              'result': result,
            });
          } catch (e) {
            sendPort.send({
              'status': 'error',
              'commandId': commandId,
              'error': e.toString(),
            });
          }
        } else if (data['command'] == 'samplesAvailable') {
          final commandId = data['commandId'] as String;
          try {
            final result = inlet.samplesAvailable();
            sendPort.send({
              'status': 'success',
              'commandId': commandId,
              'result': result,
            });
          } catch (e) {
            sendPort.send({
              'status': 'error',
              'commandId': commandId,
              'error': e.toString(),
            });
          }
        }
      }
    }
  }

  static void _resolverWorker(Map<String, dynamic> message) async {
    final msg = _ResolverMsg.fromMap(message['config']);
    final sendPort = message['sendPort'] as SendPort;
    final receivePort = ReceivePort();

    sendPort.send({'port': receivePort.sendPort, 'status': 'ready'});

    // Create the resolver
    final lsl = LSL._internal();
    final resolver = LSLStreamResolverContinuous(
      maxStreams: msg.maxStreams,
      forgetAfter: msg.forgetAfter,
    );
    resolver.create();

    // If continuous mode, set up a Timer to periodically check for streams
    Timer? periodicCheck;
    if (msg.continuous) {
      periodicCheck = Timer.periodic(
        Duration(milliseconds: (msg.waitTime * 1000).toInt()),
        (_) async {
          try {
            final streams = await resolver.resolve(waitTime: msg.waitTime);
            final streamMaps =
                streams
                    .map(
                      (s) => {
                        'streamName': s.streamName,
                        'streamType': s.streamType.value,
                        'channelCount': s.channelCount,
                        'sampleRate': s.sampleRate,
                        'channelFormat': s.channelFormat.index,
                        'sourceId': s.sourceId,
                      },
                    )
                    .toList();

            sendPort.send({'status': 'streams', 'streams': streamMaps});
          } catch (e) {
            sendPort.send({'status': 'error', 'error': e.toString()});
          }
        },
      );
    }

    // Handle messages
    await for (final data in receivePort) {
      if (data == 'destroy') {
        periodicCheck?.cancel();
        resolver.destroy();
        lsl.destroy();
        Isolate.exit();
      } else if (data is Map<String, dynamic>) {
        if (data['command'] == 'resolve') {
          final waitTime = data['waitTime'] as double;
          final commandId = data['commandId'] as String;
          try {
            final streams = await resolver.resolve(waitTime: waitTime);
            final streamMaps =
                streams
                    .map(
                      (s) => {
                        'streamName': s.streamName,
                        'streamType': s.streamType.value,
                        'channelCount': s.channelCount,
                        'sampleRate': s.sampleRate,
                        'channelFormat': s.channelFormat.index,
                        'sourceId': s.sourceId,
                      },
                    )
                    .toList();

            sendPort.send({
              'status': 'success',
              'commandId': commandId,
              'streams': streamMaps,
            });
          } catch (e) {
            sendPort.send({
              'status': 'error',
              'commandId': commandId,
              'error': e.toString(),
            });
          }
        }
      }
    }
  }

  LSL() {
    // Regular constructor - this is what users will call
  }

  // Internal constructor - used inside isolates
  LSL._internal();

  /// Returns the version of the LSL library.
  int get version => lsl_library_version();

  /// Returns the local clock time, used to calculate offsets.
  double localClock() => lsl_local_clock();

  /// Creates a new [LSLStreamInfo] object.
  ///
  /// [streamName] is the name of the stream.
  /// [streamType] is the [LSLContentType] of the stream (e.g. EEG, mocap, ...).
  /// [channelCount] is the number of channels in the stream.
  /// [sampleRate] is the stream's sample rate (Hz).
  /// [channelFormat] is the stream's [LSLChannelFormat] (e.g. string, int8).
  /// [sourceId] is the source ID of the stream which should be unique.
  Future<LSLStreamInfo> createStreamInfo({
    String streamName = "DartLSLStream",
    LSLContentType streamType = LSLContentType.eeg,
    int channelCount = 1,
    double sampleRate = 150.0,
    LSLChannelFormat channelFormat = LSLChannelFormat.float32,
    String sourceId = "DartLSL",
  }) async {
    final streamInfo = LSLStreamInfo(
      streamName: streamName,
      streamType: streamType,
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: channelFormat,
      sourceId: sourceId,
    );
    streamInfo.create();
    return streamInfo;
  }

  /// Creates a new stream outlet.
  ///
  /// This outlet runs in a separate isolate. The API handles all threading
  /// concerns transparently.
  ///
  /// [streamInfo] is the stream info to use for this outlet.
  /// [chunkSize] determines how to hand off samples to the buffer,
  /// 0 creates a chunk for each push.
  ///
  /// [maxBuffer] determines the size of the buffer that stores incoming
  /// samples. NOTE: This is in seconds, if the stream has a sample rate,
  /// otherwise it is in 100s of samples (maxBuffer * 10^2).
  Future<LSLStreamOutlet> createOutlet({
    required LSLStreamInfo streamInfo,
    int chunkSize = 0,
    int maxBuffer = 360,
  }) async {
    if (!streamInfo.created) {
      throw LSLException('StreamInfo not created');
    }

    final outletId =
        'outlet_${DateTime.now().millisecondsSinceEpoch}_${_isolates.length}';
    final receivePort = ReceivePort();

    // Prepare config for the isolate
    final config = _OutletMsg(
      streamInfo: _StreamInfoMsg(
        streamName: streamInfo.streamName,
        streamType: streamInfo.streamType,
        channelCount: streamInfo.channelCount,
        sampleRate: streamInfo.sampleRate,
        channelFormat: streamInfo.channelFormat,
        sourceId: streamInfo.sourceId,
      ),
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
    );

    // Spawn the isolate
    final isolate = await Isolate.spawn(_outletWorker, {
      'config': config.toMap(),
      'sendPort': receivePort.sendPort,
    }, debugName: outletId);

    // Wait for the isolate to initialize
    final isolateInfo = await receivePort.first as Map<String, dynamic>;
    final sendPort = isolateInfo['port'] as SendPort;

    // Store references for cleanup
    _isolates[outletId] = isolate;
    _sendPorts[outletId] = sendPort;

    // Create a proxy outlet
    return _ProxyStreamOutlet(
      owner: this,
      id: outletId,
      sendPort: sendPort,
      streamInfo: streamInfo,
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
    );
  }

  /// Creates a new stream inlet.
  ///
  /// This inlet runs in a separate isolate. The API handles all threading
  /// concerns transparently.
  ///
  /// [streamInfo] is the [LSLStreamInfo] object to be used. Probably obtained
  /// from a [LSLStreamResolver].
  /// [maxBufferSize] this is the either seconds (if [streamInfo.sampleRate]
  /// is specified) or 100s of samples (if not).
  /// [maxChunkLength] is the maximum number of samples. If 0, the default
  /// chunk length from the stream is used.
  /// [recover] is whether to recover from lost samples.
  Future<LSLStreamInlet> createInlet({
    required LSLStreamInfo streamInfo,
    int maxBufferSize = 360,
    int maxChunkLength = 0,
    bool recover = true,
  }) async {
    if (!streamInfo.created) {
      throw LSLException('StreamInfo not created');
    }

    final inletId =
        'inlet_${DateTime.now().millisecondsSinceEpoch}_${_isolates.length}';
    final receivePort = ReceivePort();

    // Prepare config for the isolate
    final config = _InletMsg(
      streamInfo: _StreamInfoMsg(
        streamName: streamInfo.streamName,
        streamType: streamInfo.streamType,
        channelCount: streamInfo.channelCount,
        sampleRate: streamInfo.sampleRate,
        channelFormat: streamInfo.channelFormat,
        sourceId: streamInfo.sourceId,
      ),
      maxBufferSize: maxBufferSize,
      maxChunkLength: maxChunkLength,
      recover: recover,
    );

    // Spawn the isolate
    final isolate = await Isolate.spawn(_inletWorker, {
      'config': config.toMap(),
      'sendPort': receivePort.sendPort,
    }, debugName: inletId);

    // Wait for the isolate to initialize
    final isolateInfo = await receivePort.first as Map<String, dynamic>;
    final sendPort = isolateInfo['port'] as SendPort;

    // Store references for cleanup
    _isolates[inletId] = isolate;
    _sendPorts[inletId] = sendPort;

    // Create a proxy inlet
    switch (streamInfo.channelFormat.dartType) {
      case const (double):
        return _ProxyStreamInlet<double>(
          owner: this,
          id: inletId,
          sendPort: sendPort,
          streamInfo: streamInfo,
        );
      case const (int):
        return _ProxyStreamInlet<int>(
          owner: this,
          id: inletId,
          sendPort: sendPort,
          streamInfo: streamInfo,
        );
      case const (String):
        return _ProxyStreamInlet<String>(
          owner: this,
          id: inletId,
          sendPort: sendPort,
          streamInfo: streamInfo,
        );
      default:
        throw LSLException('Invalid channel format');
    }
  }

  /// Resolves streams available on the network.
  ///
  /// [waitTime] is the time to wait for streams to resolve.
  /// [maxStreams] is the maximum number of streams to resolve.
  /// [forgetAfter] is the time to forget streams that are not seen.
  Future<List<LSLStreamInfo>> resolveStreams({
    double waitTime = 5.0,
    int maxStreams = 5,
    double forgetAfter = 5.0,
  }) async {
    final resolverId = 'resolver_${DateTime.now().millisecondsSinceEpoch}';
    final receivePort = ReceivePort();

    // Prepare config for the isolate
    final config = _ResolverMsg(
      waitTime: waitTime,
      maxStreams: maxStreams,
      forgetAfter: forgetAfter,
      continuous: false,
    );

    // Spawn the isolate
    final isolate = await Isolate.spawn(_resolverWorker, {
      'config': config.toMap(),
      'sendPort': receivePort.sendPort,
    }, debugName: resolverId);

    // Wait for the isolate to initialize
    final isolateInfo = await receivePort.first as Map<String, dynamic>;
    final sendPort = isolateInfo['port'] as SendPort;

    // Request stream resolution
    final commandId = 'resolve_${DateTime.now().millisecondsSinceEpoch}';
    sendPort.send({
      'command': 'resolve',
      'waitTime': waitTime,
      'commandId': commandId,
    });

    // Wait for the response
    final responsePort = ReceivePort();
    final completer = Completer<List<LSLStreamInfo>>();

    receivePort.listen((message) {
      if (message is Map<String, dynamic> &&
          message['status'] == 'success' &&
          message['commandId'] == commandId) {
        final streamMaps = List<Map<String, dynamic>>.from(message['streams']);
        final streamInfos =
            streamMaps.map((map) {
              return LSLStreamInfo(
                streamName: map['streamName'],
                streamType: LSLContentType.values.firstWhere(
                  (t) => t.value == map['streamType'],
                  orElse: () => LSLContentType.custom(map['streamType']),
                ),
                channelCount: map['channelCount'],
                sampleRate: map['sampleRate'],
                channelFormat: LSLChannelFormat.values[map['channelFormat']],
                sourceId: map['sourceId'],
              )..create();
            }).toList();

        completer.complete(streamInfos);
      } else if (message is Map<String, dynamic> &&
          message['status'] == 'error') {
        completer.completeError(LSLException(message['error']));
      }
    });

    try {
      return await completer.future.timeout(
        Duration(seconds: waitTime.toInt() + 1),
      );
    } finally {
      // Clean up
      sendPort.send('destroy');
      receivePort.close();
      responsePort.close();
      isolate.kill();
    }
  }

  /// Creates a continuous stream resolver that emits stream info objects
  /// as they are discovered.
  ///
  /// This resolver runs in a separate isolate and periodically checks for
  /// available streams.
  ///
  /// [waitTime] is the time between checks for streams.
  /// [maxStreams] is the maximum number of streams to resolve.
  /// [forgetAfter] is the time to forget streams that are not seen.
  Stream<List<LSLStreamInfo>> createContinuousResolver({
    double waitTime = 1.0,
    int maxStreams = 5,
    double forgetAfter = 5.0,
  }) async* {
    final resolverId = 'resolver_${DateTime.now().millisecondsSinceEpoch}';
    final receivePort = ReceivePort();

    // Prepare config for the isolate
    final config = _ResolverMsg(
      waitTime: waitTime,
      maxStreams: maxStreams,
      forgetAfter: forgetAfter,
      continuous: true,
    );

    // Spawn the isolate
    final isolate = await Isolate.spawn(_resolverWorker, {
      'config': config.toMap(),
      'sendPort': receivePort.sendPort,
    }, debugName: resolverId);

    // Store references for cleanup
    _isolates[resolverId] = isolate;

    // Create a stream controller for the continuous updates
    final controller = StreamController<List<LSLStreamInfo>>(
      onCancel: () {
        // Clean up when the stream is cancelled
        if (_sendPorts.containsKey(resolverId)) {
          _sendPorts[resolverId]?.send('destroy');
          _sendPorts.remove(resolverId);
        }
        if (_isolates.containsKey(resolverId)) {
          _isolates[resolverId]?.kill();
          _isolates.remove(resolverId);
        }
        receivePort.close();
        _controllerMap.remove(resolverId);
      },
    );

    _controllerMap[resolverId] = controller;

    // Handle messages from the isolate
    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        if (message['status'] == 'ready') {
          _sendPorts[resolverId] = message['port'] as SendPort;
        } else if (message['status'] == 'streams') {
          final streamMaps = List<Map<String, dynamic>>.from(
            message['streams'],
          );
          final streamInfos =
              streamMaps.map((map) {
                return LSLStreamInfo(
                  streamName: map['streamName'],
                  streamType: LSLContentType.values.firstWhere(
                    (t) => t.value == map['streamType'],
                    orElse: () => LSLContentType.custom(map['streamType']),
                  ),
                  channelCount: map['channelCount'],
                  sampleRate: map['sampleRate'],
                  channelFormat: LSLChannelFormat.values[map['channelFormat']],
                  sourceId: map['sourceId'],
                )..create();
              }).toList();

          controller.add(streamInfos);
        } else if (message['status'] == 'error') {
          controller.addError(LSLException(message['error']));
        }
      }
    });

    yield* controller.stream;
  }

  /// Destroys all resources created by this LSL instance.
  void destroy() {
    for (final id in _isolates.keys.toList()) {
      _cleanupIsolate(id);
    }
    _isolates.clear();
    _sendPorts.clear();

    for (final controller in _controllerMap.values) {
      controller.close();
    }
    _controllerMap.clear();
  }

  // Internal method to clean up an isolate
  void _cleanupIsolate(String id) {
    if (_sendPorts.containsKey(id)) {
      _sendPorts[id]?.send('destroy');
      _sendPorts.remove(id);
    }
    if (_isolates.containsKey(id)) {
      _isolates[id]?.kill();
      _isolates.remove(id);
    }
  }
}

// Proxy classes that communicate with the actual implementations in isolates

class _ProxyStreamOutlet extends LSLStreamOutlet {
  final LSL owner;
  final String id;
  final SendPort sendPort;

  _ProxyStreamOutlet({
    required this.owner,
    required this.id,
    required this.sendPort,
    required super.streamInfo,
    required super.chunkSize,
    required super.maxBuffer,
  }) {
    // Mark as created since the actual creation happens in the isolate
    super.create();
  }

  @override
  create() {
    // No-op, already created in constructor
    return this;
  }

  @override
  Future<int> pushSample(List<dynamic> data) async {
    if (data.length != streamInfo.channelCount) {
      throw LSLException(
        'Data length (${data.length}) does not match channel count (${streamInfo.channelCount})',
      );
    }

    final commandId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    final responsePort = ReceivePort();
    final completer = Completer<int>();

    // Send the sample to the isolate
    sendPort.send({'command': 'push', 'data': data, 'commandId': commandId});

    // Listen for the response
    responsePort.listen((message) {
      if (message is Map<String, dynamic> &&
          message['commandId'] == commandId) {
        if (message['status'] == 'success') {
          completer.complete(message['result']);
        } else if (message['status'] == 'error') {
          completer.completeError(LSLException(message['error']));
        }
        responsePort.close();
      }
    });

    return completer.future;
  }

  @override
  Future<void> waitForConsumer({
    double timeout = 60,
    bool exception = true,
  }) async {
    final commandId =
        'waitForConsumer_${DateTime.now().millisecondsSinceEpoch}';
    final responsePort = ReceivePort();
    final completer = Completer<void>();

    // Send the command to the isolate
    sendPort.send({
      'command': 'waitForConsumer',
      'timeout': timeout,
      'exception': exception,
      'commandId': commandId,
    });

    // Listen for the response
    responsePort.listen((message) {
      if (message is Map<String, dynamic> &&
          message['commandId'] == commandId) {
        if (message['status'] == 'success') {
          completer.complete();
        } else if (message['status'] == 'error') {
          completer.completeError(LSLException(message['error']));
        }
        responsePort.close();
      }
    });

    return completer.future;
  }

  @override
  void destroy() {
    owner._cleanupIsolate(id);
    super.destroy();
  }
}

class _ProxyStreamInlet<T> extends LSLStreamInlet<T> {
  final LSL owner;
  final String id;
  final SendPort sendPort;

  _ProxyStreamInlet({
    required this.owner,
    required this.id,
    required this.sendPort,
    required LSLStreamInfo streamInfo,
  }) : super(
         streamInfo,
         maxBufferSize: 360, // These values don't matter for the proxy
         maxChunkLength: 0,
         recover: true,
       ) {
    // Mark as created since the actual creation happens in the isolate
    super.create();
  }

  @override
  create() {
    // No-op, already created in constructor
    return this;
  }

  @override
  Future<LSLSample<T>> pullSample({double timeout = 0.0}) async {
    final commandId = 'pullSample_${DateTime.now().millisecondsSinceEpoch}';
    final responsePort = ReceivePort();
    final completer = Completer<LSLSample<T>>();

    // Send the command to the isolate
    sendPort.send({
      'command': 'pullSample',
      'timeout': timeout,
      'commandId': commandId,
    });

    // Listen for the response
    responsePort.listen((message) {
      if (message is Map<String, dynamic> &&
          message['commandId'] == commandId) {
        if (message['status'] == 'success') {
          final data = List<dynamic>.from(message['data']).cast<T>();
          final timestamp = message['timestamp'] as double;
          final errorCode = message['errorCode'] as int;

          completer.complete(LSLSample<T>(data, timestamp, errorCode));
        } else if (message['status'] == 'error') {
          completer.completeError(LSLException(message['error']));
        }
        responsePort.close();
      }
    });

    return completer.future;
  }

  @override
  Future<int> flush() async {
    // This should be async for consistency, but the base class method is sync
    // We'll make it async but block for the result
    final commandId = 'flush_${DateTime.now().millisecondsSinceEpoch}';
    final responsePort = ReceivePort();
    final completer = Completer<int>();

    // Send the command to the isolate
    sendPort.send({'command': 'flush', 'commandId': commandId});

    // Listen for the response
    responsePort.listen((message) {
      if (message is Map<String, dynamic> &&
          message['commandId'] == commandId) {
        if (message['status'] == 'success') {
          completer.complete(message['result']);
        } else if (message['status'] == 'error') {
          completer.completeError(LSLException(message['error']));
        }
        responsePort.close();
      }
    });

    // Block for result
    return completer.future.timeout(const Duration(seconds: 5));
  }

  @override
  Future<int> samplesAvailable() async {
    // This should be async for consistency, but the base class method is sync
    // We'll make it async but block for the result
    final commandId =
        'samplesAvailable_${DateTime.now().millisecondsSinceEpoch}';
    final responsePort = ReceivePort();
    final completer = Completer<int>();

    // Send the command to the isolate
    sendPort.send({'command': 'samplesAvailable', 'commandId': commandId});

    // Listen for the response
    responsePort.listen((message) {
      if (message is Map<String, dynamic> &&
          message['commandId'] == commandId) {
        if (message['status'] == 'success') {
          completer.complete(message['result']);
        } else if (message['status'] == 'error') {
          completer.completeError(LSLException(message['error']));
        }
        responsePort.close();
      }
    });

    // Block for result
    return completer.future.timeout(const Duration(seconds: 5));
  }

  @override
  void destroy() {
    owner._cleanupIsolate(id);
    super.destroy();
  }
}
