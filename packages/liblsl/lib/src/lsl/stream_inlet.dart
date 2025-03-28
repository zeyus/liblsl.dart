import 'package:liblsl/native_liblsl.dart';
import 'package:liblsl/src/lsl/base.dart';
import 'package:liblsl/src/lsl/helper.dart';
import 'package:liblsl/src/lsl/sample.dart';
import 'package:liblsl/src/lsl/exception.dart';
import 'package:liblsl/src/lsl/pull_sample.dart';
import 'package:liblsl/src/lsl/stream_info.dart';

/// Representation of the lsl_inlet_struct_ from the LSL C API.
/// @note The inlet makes a copy of the info object at its construction.
class LSLStreamInlet<T> extends LSLObj {
  lsl_inlet? _streamInlet;
  late final LSLStreamInfo streamInfo;
  int maxBufferSize;
  int maxChunkLength;
  bool recover;
  late final LslPullSample _pullFn;

  /// Creates a new LSLStreamInlet object.
  ///
  /// See also [LSLStreamOutlet] for more information on the parameters.
  ///
  /// The [streamInfo] parameter is used to determine the type of data for the
  /// given inlet.
  ///
  /// The [maxBufferSize] parameter determines the size of the buffer to use
  /// in seconds if the stream has a sample rate, otherwise it is in 100s of
  /// samples. If 0, the default buffer size from the stream is used.
  /// The [maxChunkLength] parameter determines the maximum number of samples
  /// in a chunk, if 0, the default chunk length from the stream is used.
  /// The [recover] parameter determines whether the inlet should
  /// recover from lost samples.
  LSLStreamInlet(
    this.streamInfo, {
    this.maxBufferSize = 360,
    this.maxChunkLength = 0,
    this.recover = true,
  }) {
    if (streamInfo.streamInfo == null) {
      throw LSLException('StreamInfo not created');
    }
    _pullFn = LSLMapper().streamPull(streamInfo);
  }

  @override
  create() {
    if (created) {
      throw LSLException('Inlet already created');
    }
    _streamInlet = lsl_create_inlet(
      streamInfo.streamInfo!,
      maxBufferSize,
      maxChunkLength,
      recover ? 1 : 0,
    );
    if (_streamInlet == null) {
      throw LSLException('Error creating inlet');
    }
    super.create();
    return this;
  }

  /// Pulls a sample from the inlet.
  ///
  /// The [timeout] parameter determines the maximum time to wait for a sample
  /// to arrive. To wait indefinitely, set [timeout] to [LSL_FOREVER].
  /// If [timeout] is 0, the function will return immediately with available
  /// samples, but there is no guarantee that it will return a sample.
  /// values.
  Future<LSLSample<T>> pullSample({double timeout = 0.0}) async {
    if (_streamInlet == null) {
      throw LSLException('Inlet not created');
    }

    return _pullFn(_streamInlet!, streamInfo.channelCount, timeout)
        as LSLSample<T>;
  }

  /// Clears all samples from the inlet.
  int flush() {
    if (_streamInlet == null) {
      throw LSLException('Inlet not created');
    }
    return lsl_inlet_flush(_streamInlet!);
  }

  /// Gets the number of samples available in the inlet.
  /// This will either be the number of available samples (if supported by the
  /// platform) or it will be 1 if there are samples available, or 0 if there
  /// are no samples available.
  int samplesAvailable() {
    if (_streamInlet == null) {
      throw LSLException('Inlet not created');
    }
    return lsl_samples_available(_streamInlet!);
  }

  @override
  void destroy() {
    if (destroyed) {
      return;
    }
    if (_streamInlet != null) {
      lsl_destroy_inlet(_streamInlet!);
    }
    streamInfo.destroy();
    super.destroy();
  }

  lsl_inlet? get nativeInlet => _streamInlet;
}
