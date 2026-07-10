import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

class ModelManager {
  static const String gemmaUrl = "https://huggingface.co/lmstudio-ai/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-q4_k_m.gguf";
  static const String whisperUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin";

  static const String gemmaFileName = "gemma-2b.gguf";
  static const String whisperFileName = "whisper-tiny.bin";

  Future<String> getModelPath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, "models", fileName);
  }

  Future<bool> areModelsDownloaded() async {
    final gemmaPath = await getModelPath(gemmaFileName);
    final whisperPath = await getModelPath(whisperFileName);
    return File(gemmaPath).existsSync() && File(whisperPath).existsSync();
  }

  Stream<double> downloadModels() async* {
    final directory = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(p.join(directory.path, "models"));
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final dio = Dio();
    
    // Download Whisper
    final whisperPath = p.join(modelsDir.path, whisperFileName);
    if (!File(whisperPath).existsSync()) {
      yield* _downloadFile(dio, whisperUrl, whisperPath, 0, 0.2); // 20% of total
    } else {
      yield 0.2;
    }

    // Download Gemma
    final gemmaPath = p.join(modelsDir.path, gemmaFileName);
    if (!File(gemmaPath).existsSync()) {
      yield* _downloadFile(dio, gemmaUrl, gemmaPath, 0.2, 1.0); // Remaining 80%
    } else {
      yield 1.0;
    }
  }

  Stream<double> _downloadFile(Dio dio, String url, String savePath, double startProgress, double endProgress) async* {
    double currentProgress = startProgress;
    
    await dio.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total != -1) {
          double fileProgress = received / total;
          currentProgress = startProgress + (fileProgress * (endProgress - startProgress));
          // We can't yield here directly from a callback, so we'll need a different approach if we want real-time.
          // But for now, we'll use a StreamController or similar in a real app.
        }
      },
    );
    yield endProgress;
  }

  // Improved download with StreamController for real-time progress
  Stream<double> downloadWithProgress() {
    final controller = StreamController<double>();
    _startDownload(controller);
    return controller.stream;
  }

  Future<void> _startDownload(StreamController<double> controller) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(p.join(directory.path, "models"));
      if (!modelsDir.existsSync()) modelsDir.createSync(recursive: true);

      final dio = Dio();
      double totalProgress = 0;

      // Helper for nested progress
      Future<void> downloadOne(String url, String path, double weight) async {
        await dio.download(url, path, onReceiveProgress: (received, total) {
          if (total != -1) {
            double p = (received / total) * weight;
            controller.add(totalProgress + p);
          }
        });
        totalProgress += weight;
        controller.add(totalProgress);
      }

      final whisperPath = p.join(modelsDir.path, whisperFileName);
      final wFile = File(whisperPath);
      // Only delete if it's obviously truncated (less than 75MB)
      if (wFile.existsSync() && wFile.lengthSync() < 75000000) wFile.deleteSync();
      
      if (!wFile.existsSync()) {
        await downloadOne(whisperUrl, whisperPath, 0.1); // Whisper is small
      } else {
        totalProgress += 0.1;
      }

      final gemmaPath = p.join(modelsDir.path, gemmaFileName);
      final gFile = File(gemmaPath);
      if (gFile.existsSync() && gFile.lengthSync() <= 1400000000) gFile.deleteSync();

      if (!gFile.existsSync()) {
        await downloadOne(gemmaUrl, gemmaPath, 0.9); // Gemma is large
      } else {
        totalProgress += 0.9;
      }

      controller.close();
    } catch (e) {
      controller.addError(e);
      controller.close();
    }
  }

  Future<bool> verifyIntegrity() async {
    try {
      final gemmaPath = await getModelPath(gemmaFileName);
      final whisperPath = await getModelPath(whisperFileName);
      
      final gFile = File(gemmaPath);
      final wFile = File(whisperPath);
      
      // Whisper Tiny is ~77MB. Gemma 2B is ~1.49GB.
      bool gValid = gFile.existsSync() && gFile.lengthSync() > 1400000000;
      bool wValid = wFile.existsSync() && wFile.lengthSync() > 75000000;   // Allow any valid fully downloaded Whisper model > 75MB
      
      if (gValid && wValid) {
        print("AI MODELS DETECTED: Files found on device storage. (Gemma: ${gFile.lengthSync()} bytes, Whisper: ${wFile.lengthSync()} bytes)");
        return true;
      } else {
        print("AI MODELS MISSING: Files not found or corrupted.");
        return false;
      }
    } catch (e) {
      print("Error verifying models: $e");
      return false;
    }
  }
}
