import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// M2: Face Embedding Module using AdaFace-Mobile
/// Converts cropped face images into numerical vectors (embeddings)
/// Using AdaFace-Mobile model (better than MobileFaceNet)
class FaceEmbeddingModule {
  static const String modelName = 'AdaFace-Mobile';
  static const int embeddingDimension =
      512; // AdaFace-Mobile outputs 512D vectors
  static const String modelAssetPath = 'assets/models/embedding_model.tflite';

  Interpreter? _interpreter;
  bool _isInitialized = false;

  /// Initialize the AdaFace-Mobile model
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        modelAssetPath,
        options: options,
      );
      _interpreter?.allocateTensors();
      _isInitialized = true;
    } catch (e) {
      _interpreter?.close();
      _interpreter = null;
      _isInitialized = false;
      throw Exception('AdaFace-Mobile init failed: $e');
    }
  }

  /// Generate face embedding from cropped face image
  /// Input: Cropped face image (uint8 bytes)
  /// Output: Embedding vector (list of doubles)
  Future<List<double>?> generateEmbedding(Uint8List faceImageBytes) async {
    if (!_isInitialized) await initialize();
    if (_interpreter == null) return null;

    try {
      // Decode and preprocess image
      final image = img.decodeImage(faceImageBytes);
      if (image == null) return null;

      // Resize to model input size (112x112 for AdaFace-Mobile)
      final resized = img.copyResize(image, width: 112, height: 112);

      // Convert to RGB float array
      final inputBuffer = Float32List(112 * 112 * 3);
      var index = 0;

      for (var y = 0; y < 112; y++) {
        for (var x = 0; x < 112; x++) {
          final pixel = resized.getPixel(x, y);
          inputBuffer[index++] = pixel.r / 255.0; // R
          inputBuffer[index++] = pixel.g / 255.0; // G
          inputBuffer[index++] = pixel.b / 255.0; // B
        }
      }

      // Prepare input tensor
      final inputShape = [1, 112, 112, 3];
      final inputData = inputBuffer.reshape(inputShape);

      // Run inference
      _interpreter!.run(inputData, {});

      // Get output and safely convert to Float32List
      final outputTensor = _interpreter!.getOutputTensors().first;
      final rawData = outputTensor.data;
      
      // Handle different data types that TFLite might return
      // ignore: unnecessary_type_check
      late List<double> embedding;
      if (rawData is Float32List) {
        embedding = rawData.toList().cast<double>();
      } else {
        // Handle Uint8List, generic List, or any other iterable
        // ignore: unnecessary_type_check
        final list = rawData as List;
        embedding = list.map((v) => (v as num).toDouble()).toList();
      }

      return normalizeEmbedding(embedding);
    } catch (e) {
      print('Error generating embedding: $e');
      return null;
    }
  }

  /// Normalize embedding vector (L2 normalization)
  /// Ensures vector has unit norm for cosine similarity
  List<double> normalizeEmbedding(List<double> embedding) {
    if (embedding.isEmpty) return embedding;
    final norm = _calculateNorm(embedding);
    if (norm == 0 || norm.isNaN) return embedding;
    return embedding.map((e) => e / norm).toList();
  }

  /// Calculate L2 norm of vector
  double _calculateNorm(List<double> vector) {
    double sum = 0;
    for (final v in vector) {
      sum += v * v;
    }
    return sum > 0 ? _sqrt(sum) : 0;
  }

  /// Simple square root approximation
  double _sqrt(double x) {
    if (x == 0) return 0;
    double z = x;
    double result = 0;
    while ((z - result).abs() > 1e-7) {
      result = z;
      z = 0.5 * (z + x / z);
    }
    return z;
  }

  /// Validate embedding
  bool isValidEmbedding(List<double> embedding) {
    return embedding.length == embeddingDimension &&
        embedding.every((e) => e.isFinite);
  }

  /// Get embedding statistics
  Map<String, dynamic> getEmbeddingStats(List<double> embedding) {
    if (embedding.isEmpty) {
      return {'min': 0, 'max': 0, 'mean': 0, 'dimension': 0};
    }

    double min = embedding[0];
    double max = embedding[0];
    double sum = 0;

    for (final val in embedding) {
      if (val < min) min = val;
      if (val > max) max = val;
      sum += val;
    }

    return {
      'dimension': embedding.length,
      'min': min.toStringAsFixed(4),
      'max': max.toStringAsFixed(4),
      'mean': (sum / embedding.length).toStringAsFixed(4),
    };
  }

  /// Dispose resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }

  /// Indicates whether the interpreter is ready for inference
  bool get isReady => _isInitialized && _interpreter != null;
}
