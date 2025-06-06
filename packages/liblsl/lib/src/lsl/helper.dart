import 'dart:ffi';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/push_sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';
import 'package:liblsl/src/lsl/structs.dart';

/// LSLMapper type mapping.
///
/// Handles a lot of the complexity of converting between the
/// LSL / FFI [NativeType] types and dart [Type] types.
/// @note This class is a singleton, so it should be used as a static class.
class LSLMapper {
  static LSLMapper? _instance;

  /// Map of [StreamInfo.channelFormat] to [LslPushSample].
  static final Map<LSLChannelFormat, LslPushSample> _pushSampleMap = {
    LSLChannelFormat.float32: LslPushSampleFloat(),
    LSLChannelFormat.double64: LslPushSampleDouble(),
    LSLChannelFormat.int8: LslPushSampleInt8(),
    LSLChannelFormat.int16: LslPushSampleInt16(),
    LSLChannelFormat.int32: LslPushSampleInt32(),
    LSLChannelFormat.int64: LslPushSampleInt64(),
    LSLChannelFormat.string: LslPushSampleString(),
    LSLChannelFormat.undefined: LslPushSampleVoid(),
  };

  /// Map of [StreamInfo.channelFormat] to [LslPullSample].
  static final Map<LSLChannelFormat, LslPullSample> _pullSampleMap = {
    LSLChannelFormat.float32: LslPullSampleFloat(),
    LSLChannelFormat.double64: LslPullSampleDouble(),
    LSLChannelFormat.int8: LslPullSampleInt8(),
    LSLChannelFormat.int16: LslPullSampleInt16(),
    LSLChannelFormat.int32: LslPullSampleInt32(),
    LSLChannelFormat.int64: LslPullSampleInt64(),
    LSLChannelFormat.string: LslPullSampleString(),
    LSLChannelFormat.undefined: LslPullSampleUndefined(),
  };

  LSLMapper._();

  factory LSLMapper() {
    _instance ??= LSLMapper._();
    return _instance!;
  }

  Map<LSLChannelFormat, LslPushSample> get pushSampleMap => _pushSampleMap;
  Map<LSLChannelFormat, LslPullSample> get pullSampleMap => _pullSampleMap;

  /// Gets the [LslPushSample] for the given [LSLStreamInfo].
  LslPushSample streamPush(LSLStreamInfo streamInfo) {
    final LSLChannelFormat channelFormat = streamInfo.channelFormat;
    if (_pushSampleMap.containsKey(channelFormat)) {
      return _pushSampleMap[channelFormat]!;
    } else {
      throw LSLException('Unsupported channel format: $channelFormat');
    }
  }

  /// Gets the [LslPullSample] for the given [LSLStreamInfo].
  LslPullSample streamPull(LSLStreamInfo streamInfo) {
    final LSLChannelFormat channelFormat = streamInfo.channelFormat;
    if (_pullSampleMap.containsKey(channelFormat)) {
      return _pullSampleMap[channelFormat]!;
    } else {
      throw LSLException('Unsupported channel format: $channelFormat');
    }
  }
}
