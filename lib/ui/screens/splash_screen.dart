import 'package:flutter/material.dart';

import '../../core/ai/model_manager.dart';
import 'sessions_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final ModelManager _modelManager = ModelManager();
  double _progress = 0;
  String _status = "Initializing AI...";
  bool _isDownloading = false;
  late AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initApp();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    await Future.delayed(const Duration(seconds: 1)); // Short delay for logo intro
    final downloaded = await _modelManager.areModelsDownloaded();
    if (downloaded) {
      final intact = await _modelManager.verifyIntegrity();
      if (intact) {
        _navigateToHome();
      } else {
        _startDownload();
      }
    } else {
      _startDownload();
    }
  }

  void _startDownload() {
    setState(() {
      _isDownloading = true;
      _status = "Fetching AI Brain (1.2GB)...";
    });

    _modelManager.downloadWithProgress().listen(
      (progress) {
        setState(() {
          _progress = progress;
        });
      },
      onError: (e) {
        setState(() {
          _status = "Error: Connection lost. Retrying...";
        });
      },
      onDone: () async {
        if (await _modelManager.verifyIntegrity()) {
          _navigateToHome();
        } else {
          _startDownload();
        }
      },
    );
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const SessionsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              ),
            ),
          ),
          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 1.0, end: 1.05).animate(
                    CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.2),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 180,
                      height: 180,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  "GEMMA AI",
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "OFFLINE TRANSLATOR",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueAccent,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 80),
                if (_isDownloading) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 6,
                            backgroundColor: Colors.white10,
                            color: Colors.blueAccent,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "${(_progress * 100).toInt()}% DOWNLOADED",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blueAccent,
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  _status,
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Bottom Info
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              "POWERED BY GOOGLE GEMMA • ON-DEVICE AI",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: Colors.white24,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
