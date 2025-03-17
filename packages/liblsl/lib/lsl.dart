import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show calloc, StringUtf8Pointer;
import 'package:liblsl/liblsl.dart';
import 'src/types.dart';
import 'src/ffi/mem.dart';

typedef DartLslPushSample<T extends NativeType> =
    int Function(lsl_outlet out, Pointer<T> data);

typedef DartLslPushSampleTs<T extends NativeType> =
    int Function(lsl_outlet out, Pointer<T> data, double timestamp);

typedef DartLslPullSample<T extends NativeType> =
    double Function(
      lsl_inlet in$,
      Pointer<T> buffer,
      int bufferElements,
      double timeout,
      Pointer<Int32> ec,
    );

// Create a wrapper class to handle the different types
class LslPushSample<T extends NativeType> {
  final DartLslPushSample<T> _pushFn;

  const LslPushSample(this._pushFn);

  int call(lsl_outlet out, Pointer<T> data) {
    return _pushFn(out, data);
  }
}

enum LSLContentType {
  /// EEG (for Electroencephalogram)
  eeg("EEG"),

  /// MoCap (for Motion Capture)
  mocap("MoCap"),

  /// NIRS (Near-Infrared Spectroscopy)
  nirs("NIRS"),

  /// Gaze (for gaze / eye tracking parameters)
  gaze("Gaze"),

  /// VideoRaw (for uncompressed video)
  videoRaw("VideoRaw"),

  /// VideoCompressed (for compressed video)
  videoCompressed("VideoCompressed"),

  /// Audio (for PCM-encoded audio)
  audio("Audio"),

  /// Markers (for event marker streams)
  markers("Markers");

  final String value;

  const LSLContentType(this.value);

  Pointer<Char> get charPtr =>
      value.toNativeUtf8(allocator: allocate) as Pointer<Char>;
}

enum LSLChannelFormat {
  float32,
  double64,
  int8,
  int16,
  int32,
  int64,
  string,
  undefined;

  lsl_channel_format_t get lslFormat {
    switch (this) {
      case LSLChannelFormat.float32:
        return lsl_channel_format_t.cft_float32;
      case LSLChannelFormat.double64:
        return lsl_channel_format_t.cft_double64;
      case LSLChannelFormat.int8:
        return lsl_channel_format_t.cft_int8;
      case LSLChannelFormat.int16:
        return lsl_channel_format_t.cft_int16;
      case LSLChannelFormat.int32:
        return lsl_channel_format_t.cft_int32;
      case LSLChannelFormat.int64:
        return lsl_channel_format_t.cft_int64;
      case LSLChannelFormat.string:
        return lsl_channel_format_t.cft_string;
      case LSLChannelFormat.undefined:
        return lsl_channel_format_t.cft_undefined;
    }
  }

  Type get ffiType {
    switch (this) {
      case LSLChannelFormat.float32:
        return Float;
      case LSLChannelFormat.double64:
        return Double;
      case LSLChannelFormat.int8:
        return Int8;
      case LSLChannelFormat.int16:
        return Int16;
      case LSLChannelFormat.int32:
        return Int32;
      case LSLChannelFormat.int64:
        return Int64;
      case LSLChannelFormat.string:
        return Pointer<Char>;
      case LSLChannelFormat.undefined:
        return Void;
    }
  }

  LslPushSample get pushFn {
    switch (this) {
      case LSLChannelFormat.float32:
        return LslPushSample<Float>(lsl_push_sample_f);
      case LSLChannelFormat.double64:
        return LslPushSample<Double>(lsl_push_sample_d);
      case LSLChannelFormat.int8:
        return LslPushSample<Char>(lsl_push_sample_c);
      case LSLChannelFormat.int16:
        return LslPushSample<Int16>(lsl_push_sample_s);
      case LSLChannelFormat.int32:
        return LslPushSample<Int32>(lsl_push_sample_i);
      case LSLChannelFormat.int64:
        return LslPushSample<Int64>(lsl_push_sample_l);
      case LSLChannelFormat.string:
        return LslPushSample<Pointer<Char>>(lsl_push_sample_str);
      case LSLChannelFormat.undefined:
        return LslPushSample<Void>(lsl_push_sample_v);
    }
  }

  DartLslPushSampleTs get pushFnTs {
    switch (this) {
      case LSLChannelFormat.float32:
        return lsl_push_sample_ft as DartLslPushSampleTs;
      case LSLChannelFormat.double64:
        return lsl_push_sample_dt as DartLslPushSampleTs;
      case LSLChannelFormat.int8:
        return lsl_push_sample_ct as DartLslPushSampleTs;
      case LSLChannelFormat.int16:
        return lsl_push_sample_st as DartLslPushSampleTs;
      case LSLChannelFormat.int32:
        return lsl_push_sample_it as DartLslPushSampleTs;
      case LSLChannelFormat.int64:
        return lsl_push_sample_lt as DartLslPushSampleTs;
      case LSLChannelFormat.string:
        return lsl_push_sample_strt as DartLslPushSampleTs;
      case LSLChannelFormat.undefined:
        return lsl_push_sample_vt as DartLslPushSampleTs;
    }
  }

  DartLslPullSample get pullFn {
    switch (this) {
      case LSLChannelFormat.float32:
        return lsl_pull_sample_f as DartLslPullSample;
      case LSLChannelFormat.double64:
        return lsl_pull_sample_d as DartLslPullSample;
      case LSLChannelFormat.int8:
        return lsl_pull_sample_c as DartLslPullSample;
      case LSLChannelFormat.int16:
        return lsl_pull_sample_s as DartLslPullSample;
      case LSLChannelFormat.int32:
        return lsl_pull_sample_i as DartLslPullSample;
      case LSLChannelFormat.int64:
        return lsl_pull_sample_l as DartLslPullSample;
      case LSLChannelFormat.string:
        return lsl_pull_sample_str as DartLslPullSample;
      case LSLChannelFormat.undefined:
        return lsl_pull_sample_v as DartLslPullSample;
    }
  }
}

// const Map<str, Function

/// Further bits of meta-data that can be associated with a stream are the following:

// Human-Subject Information
// Recording Environment Information
// Experiment Information
// Synchronization Information

abstract class MemManaged {
  final List<Pointer> _allocatedArgs = [];

  void freeArgs() {
    for (final arg in _allocatedArgs) {
      arg.free();
    }
    _allocatedArgs.clear();
  }
}

abstract class LSLObj extends MemManaged {
  dynamic create();
  void destroy();
  bool error(int code) {
    final e = lsl_error_code_t.fromValue(code);
    return e != lsl_error_code_t.lsl_no_error;
  }
}

class LSLSample<T extends NativeType> {
  final Pointer<T> data;

  LSLSample(this.data);
}

class LSLSampleTs<T extends NativeType> extends LSLSample<T> {
  final double timestamp;

  LSLSampleTs(super.data, this.timestamp);
}

class LSLStreamInfo extends LSLObj {
  final String streamName;
  final LSLContentType streamType;
  final int channelCount;
  final double sampleRate;
  final LSLChannelFormat channelFormat;
  final String sourceId;
  lsl_streaminfo? _streamInfo;

  LSLStreamInfo({
    this.streamName = "DartLSLStream",
    this.streamType = LSLContentType.eeg,
    this.channelCount = 16,
    this.sampleRate = 250.0,
    this.channelFormat = LSLChannelFormat.float32,
    this.sourceId = "DartLSL",
  });

  lsl_streaminfo? get streamInfo => _streamInfo;

  @override
  lsl_streaminfo create() {
    final streamNamePtr =
        streamName.toNativeUtf8(allocator: allocate) as Pointer<Char>;
    final sourceIdPtr =
        sourceId.toNativeUtf8(allocator: allocate) as Pointer<Char>;
    final streamTypePtr = streamType.charPtr;

    _allocatedArgs.addAll([streamNamePtr, sourceIdPtr, streamTypePtr]);
    _streamInfo = lsl_create_streaminfo(
      streamNamePtr,
      streamTypePtr,
      channelCount,
      sampleRate,
      channelFormat.lslFormat,
      sourceIdPtr,
    );
    return _streamInfo!;
  }

  @override
  void destroy() {
    if (_streamInfo != null) {
      lsl_destroy_streaminfo(_streamInfo!);
      _streamInfo?.free();
      _streamInfo = null;
    }
    freeArgs();
  }
}

class LSLStreamOutlet extends LSLObj {
  final LSLStreamInfo streamInfo;
  final int chunkSize;
  final int maxBuffer;
  late final LslPushSample _pushFn;
  late final DartLslPushSampleTs _pushFnTs;
  late final DartLslPullSample _pullFn;
  lsl_outlet? _streamOutlet;

  LSLStreamOutlet({
    required this.streamInfo,
    this.chunkSize = 0,
    this.maxBuffer = 1,
  }) {
    if (streamInfo.streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _pushFn = streamInfo.channelFormat.pushFn;
    // _pushFnTs = streamInfo.channelFormat.pushFnTs;
    // _pullFn = streamInfo.channelFormat.pullFn;
  }

  @override
  lsl_outlet create() {
    _streamOutlet = lsl_create_outlet(
      streamInfo.streamInfo!,
      chunkSize,
      maxBuffer,
    );
    return _streamOutlet!;
  }

  @override
  void destroy() {
    if (_streamOutlet != null) {
      lsl_destroy_outlet(_streamOutlet!);
      _streamOutlet?.free();
      _streamOutlet = null;
    }
    freeArgs();
  }

  Future<void> waitForConsumer({double timeout = 60}) async {
    final consumerFound = lsl_wait_for_consumers(_streamOutlet!, timeout);
    if (consumerFound == 0) {
      throw TimeoutException('No consumer found within $timeout seconds');
    }
  }

  Pointer _allocSample(dynamic data) {
    switch (streamInfo.channelFormat.ffiType) {
      case const (Float):
        final ptr = allocate<Float>();
        ptr.value = data;
        return ptr;
      case const (Double):
        final ptr = allocate<Double>();
        ptr.value = data;
        return ptr;
      case const (Int8):
        final ptr = allocate<Int8>();
        ptr.value = data;
        return ptr;
      case const (Int16):
        final ptr = allocate<Int16>();
        ptr.value = data;
        return ptr;
      case const (Int32):
        final ptr = allocate<Int32>();
        ptr.value = data;
        return ptr;
      case const (Int64):
        final ptr = allocate<Int64>();
        ptr.value = data;
        return ptr;
      case const (Pointer<Char>):
        // string
        if (data is String) {
          final List<String> dataList = data.split('');
          final ptrArray = calloc<Pointer<Char>>(dataList.length);
          for (var i = 0; i < dataList.length; i++) {
            ptrArray[i] = dataList[i].toNativeUtf8().cast<Char>();
          }
          return ptrArray;
        }
        throw LSLException('Invalid string data');
      case const (Void):
        return nullPtr<Void>();
      default:
        throw LSLException('Invalid sample type');
    }
  }

  Future<int> pushSample(dynamic data) async {
    final samplePtr = _allocSample(data);
    // exception with type of sampleptr
    final int result = _pushFn(_streamOutlet!, samplePtr);
    samplePtr.free();
    return result;
  }
}

// need to implement full data types later
class LSL {
  LSLStreamInfo? _streamInfo;
  LSLStreamOutlet? _streamOutlet;
  LSL();

  Future<LSLStreamInfo> createStreamInfo({
    String streamName = "DartLSLStream",
    LSLContentType streamType = LSLContentType.eeg,
    int channelCount = 16,
    double sampleRate = 250.0,
    LSLChannelFormat channelFormat = LSLChannelFormat.float32,
    String sourceId = "DartLSL",
  }) async {
    _streamInfo = LSLStreamInfo(
      streamName: streamName,
      streamType: streamType,
      channelCount: channelCount,
      sampleRate: sampleRate,
      channelFormat: channelFormat,
      sourceId: sourceId,
    );
    _streamInfo?.create();
    return _streamInfo!;
  }

  int get version => lsl_library_version();

  LSLStreamInfo? get info => _streamInfo;
  LSLStreamOutlet? get outlet => _streamOutlet;

  Future<LSLStreamOutlet> createOutlet({
    int chunkSize = 0,
    int maxBuffer = 1,
  }) async {
    if (_streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _streamOutlet = LSLStreamOutlet(
      streamInfo: _streamInfo!,
      chunkSize: chunkSize,
      maxBuffer: maxBuffer,
    );
    _streamOutlet?.create();
    return _streamOutlet!;
  }

  double localClock() => lsl_local_clock();
}
