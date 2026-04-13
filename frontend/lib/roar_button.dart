import 'dart:async';
import 'package:flutter/material.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:record/record.dart';


class RoarButton extends StatefulWidget {
  final Function(double maxDb) onFinished;
  const RoarButton({super.key, required this.onFinished});

  @override
  State<RoarButton> createState() => _RoarButtonState();
}

class _RoarButtonState extends State<RoarButton> {
  bool _isRecording = false;
  double _currentDb = 0.0;
  double _maxDb = 0.0;
  StreamSubscription<NoiseReading>? _noiseSubscription;
  final _noiseMeter = NoiseMeter();

  void _startRoaring() async {
    final recorder = AudioRecorder();
    if (await recorder.hasPermission()) {
      setState(() {
        _isRecording = true;
        _maxDb = 0.0;
      });
      _noiseSubscription = _noiseMeter.noise.listen((noiseReading) {
        setState(() {
          _currentDb = noiseReading.maxDecibel;
          if (_currentDb > _maxDb) _maxDb = _currentDb;
        });
      });
    }
  }

  void _stopRoaring() {
    _noiseSubscription?.cancel();
    setState(() => _isRecording = false);
    widget.onFinished(_maxDb);
    _currentDb = 0.0;
  }

  @override
  Widget build(BuildContext context) {
    // 音量（60dB〜100dB程度）に応じてボタンを大きくする
    double scale = 1.0 + (_isRecording ? (_currentDb - 60).clamp(0, 40) / 40 : 0);

    return GestureDetector(
      onLongPress: _startRoaring,
      onLongPressUp: _stopRoaring,
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 1.0, end: scale),
        duration: const Duration(milliseconds: 100),
        builder: (context, value, child) => Transform.scale(scale: value, child: child),
        child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: _isRecording ? Colors.orange : Colors.amber,
            boxShadow: [if (_isRecording) BoxShadow(color: Colors.orange.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
          ),
          child: Icon(_isRecording ? Icons.whatshot : Icons.mic, size: 40, color: Colors.white),
        ),
      ),
    );
  }
}