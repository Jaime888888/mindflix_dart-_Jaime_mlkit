import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔹 Lock app to landscape orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 🔹 Use front camera (webcam for emulator)
  final cameras = await availableCameras();
  final frontCamera = cameras.firstWhere(
    (cam) => cam.lensDirection == CameraLensDirection.front,
    orElse: () => cameras.first,
  );

  runApp(MyApp(camera: frontCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gaze Tracker (ML Kit)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: GazeTracker(camera: camera),
    );
  }
}

class GazeTracker extends StatefulWidget {
  final CameraDescription camera;
  const GazeTracker({super.key, required this.camera});

  @override
  State<GazeTracker> createState() => _GazeTrackerState();
}

class _GazeTrackerState extends State<GazeTracker> {
  late CameraController _controller;
  late FaceDetector _faceDetector;
  bool _isReady = false;
  bool _isRunning = false;
  int _secondsLeft = 10;
  Timer? _frameTimer;
  Timer? _countdownTimer;
  int _leftCount = 0;
  int _rightCount = 0;
  double _dotX = 0; // 👁 dot position on screen

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initFaceDetector();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.low,
      enableAudio: false,
    );
    await _controller.initialize();
    if (!mounted) return;
    setState(() => _isReady = true);
  }

  void _initFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  void _startTimer() {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _secondsLeft = 10;
      _leftCount = 0;
      _rightCount = 0;
      _dotX = MediaQuery.of(context).size.width / 2;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        timer.cancel();
        _stopTracking();
      }
    });

    _frameTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_controller.value.isInitialized || _controller.value.isTakingPicture)
        return;
      try {
        final pic = await _controller.takePicture();
        await _analyzeFrame(pic.path);
      } catch (e) {
        debugPrint("Frame error: $e");
      }
    });
  }

  Future<void> _analyzeFrame(String path) async {
    final inputImage = InputImage.fromFilePath(path);
    final faces = await _faceDetector.processImage(inputImage);
    if (faces.isEmpty) return;

    final width = MediaQuery.of(context).size.width;
    double avgX = 0;
    for (final face in faces) {
      avgX += face.boundingBox.center.dx;
    }
    avgX /= faces.length;

    // Normalize and invert so movement feels natural (mirror effect)
    double normalizedX = (1 - (avgX / 300)) * width;
    setState(() {
      _dotX = normalizedX.clamp(0, width);
    });

    // Count gaze direction
    if (normalizedX < width / 2) {
      _leftCount++;
    } else {
      _rightCount++;
    }
  }

  Future<void> _stopTracking() async {
    _frameTimer?.cancel();
    _countdownTimer?.cancel();
    setState(() => _isRunning = false);

    String result;
    if (_leftCount > _rightCount) {
      result = "👁 Looked more at LEFT image";
    } else if (_rightCount > _leftCount) {
      result = "👁 Looked more at RIGHT image";
    } else {
      result = "🤷‍♂️ Looked equally at both";
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text("Result"),
          content: Text("$_leftCount left vs $_rightCount right\n\n$result"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    _frameTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Stack(
        children: [
          // 🔹 Equal-sized images side by side
          Row(
            children: [
              Expanded(
                child: Image.asset(
                  'images/golden-retriever-tongue-out.jpg',
                  fit: BoxFit.cover,
                ),
              ),
              Expanded(
                child: Image.asset('images/orange-cat.jpg', fit: BoxFit.cover),
              ),
            ],
          ),

          // 🔹 Floating gaze dot
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            left: _dotX - 10,
            top: 40,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.6),
                    blurRadius: 8,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          ),

          // 🔹 Bottom overlay (timer + button)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isRunning
                        ? "Time left: $_secondsLeft s"
                        : "Press Start to begin",
                    style: const TextStyle(fontSize: 24, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _isRunning ? null : _startTimer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 60,
                        vertical: 20,
                      ),
                    ),
                    child: const Text(
                      "Start 10-second Test",
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
