import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import 'amplifyconfiguration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureAmplify();
  runApp(const MyApp());
}

Future<void> _configureAmplify() async {
  try {
    await Amplify.addPlugins([
      AmplifyAuthCognito(),
      AmplifyAPI(),
      AmplifyStorageS3(),
    ]);
    await Amplify.configure(amplifyconfig);
  } catch (e) {
    print('初期化エラー: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return Authenticator(
      child: MaterialApp(
        theme: ThemeData.dark(),
        builder: Authenticator.builder(),
        home: const DebugPage(),
      ),
    );
  }
}

class DebugPage extends StatefulWidget {
  const DebugPage({super.key});
  @override
  State<DebugPage> createState() => _DebugPageState();
}

class _DebugPageState extends State<DebugPage> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isRecording = false;
  String _statusMessage = "待機中...";
  String _lambdaResponse = "Lambdaからの返信はまだありません";
  String _lastS3Key = "";

  // 🎵 再生プレイヤー用の変数
  Duration _duration = Duration.zero;   // 音声の全長
  Duration _position = Duration.zero;   // 現在の再生位置
  double _volume = 0.5;                // 音量 (0.0 ～ 1.0)

  @override
  void initState() {
    super.initState();
    // 再生状態の監視設定
    _audioPlayer.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });
    _audioPlayer.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      setState(() {
        _position = _duration;
        _statusMessage = "再生完了！";
      });
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- 録音・送信ロジック ---
  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/roar_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
          _statusMessage = "録音中ガオォォ！！";
        });
      }
    } catch (e) {
      setState(() => _statusMessage = "録音エラー: $e");
    }
  }

  Future<void> _stopAndUpload() async {
    try {
      final path = await _recorder.stop();
      setState(() { _isRecording = false; _statusMessage = "処理中..."; });
      if (path == null) return;

      final key = 'public/roars/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await Amplify.Storage.uploadFile(localFile: AWSFile.fromPath(path), key: key).result;

      final user = await Amplify.Auth.getCurrentUser();
      final operation = Amplify.API.post('/roars', body: HttpPayload.json({
        "userId": user.userId,
        "userName": user.username,
        "s3Key": key,
        "roarPower": 99.9,
        "message": "サバンナからのデバッグ送信！"
      }));
      final response = await operation.response;
      
      setState(() {
        _lastS3Key = key;
        _lambdaResponse = response.decodeBody();
        _statusMessage = "送信完了だガオ！";
      });
    } catch (e) {
      setState(() => _statusMessage = "送信エラー: $e");
    }
  }

  // --- 再生ロジック ---
  Future<void> _playLastRoar() async {
    if (_lastS3Key.isEmpty) return;
    try {
      final result = await Amplify.Storage.getUrl(key: _lastS3Key).result;
      await _audioPlayer.play(UrlSource(result.url.toString()));
      setState(() => _statusMessage = "再生中...");
    } catch (e) {
      setState(() => _statusMessage = "再生エラー: $e");
    }
  }

  // 時間の表示を 00:00 形式にする補助関数
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🦁 本格デバッグ・サバンナ V2')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 1. ステータス表示
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.blueGrey[900], borderRadius: BorderRadius.circular(10)),
              child: Text("状態: $_statusMessage", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),

            // 2. プレイヤーコントロール (NEW!)
            Card(
              color: Colors.black45,
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Column(
                  children: [
                    const Text("🔈 プレイヤーコントロール", style: TextStyle(fontWeight: FontWeight.bold)),
                    // 再生バー
                    Slider(
                      value: _position.inMilliseconds.toDouble(),
                      max: _duration.inMilliseconds.toDouble() > 0 ? _duration.inMilliseconds.toDouble() : 1.0,
                      onChanged: (value) async {
                        await _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                    // 時間表示
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(_position)),
                        Text(_formatDuration(_duration)),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    // 音量調整
                    Row(
                      children: [
                        const Icon(Icons.volume_down),
                        Expanded(
                          child: Slider(
                            value: _volume,
                            onChanged: (value) {
                              setState(() => _volume = value);
                              _audioPlayer.setVolume(value);
                            },
                          ),
                        ),
                        const Icon(Icons.volume_up),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),

            // 3. 操作ボタン
            Wrap(
              spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isRecording ? _stopAndUpload : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? '止めて送信' : '吠える（録音）'),
                  style: ElevatedButton.styleFrom(backgroundColor: _isRecording ? Colors.red : Colors.orange),
                ),
                ElevatedButton.icon(
                  onPressed: _playLastRoar,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('S3から再生'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final res = await Amplify.API.get('/timeline').response;
                    setState(() => _lambdaResponse = res.decodeBody());
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('タイムライン取得'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // 4. Lambda返信エリア
            const Align(alignment: Alignment.centerLeft, child: Text("▼ APIレスポンス")),
            Container(
              width: double.infinity, height: 200, padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(5)),
              child: SingleChildScrollView(child: Text(_lambdaResponse, style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11))),
            ),
            const SizedBox(height: 20),
            const SignOutButton(),
          ],
        ),
      ),
    );
  }
}