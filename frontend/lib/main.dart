import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // 👈 追加：Webかどうかを判定する魔法
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
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),
        ),
        builder: Authenticator.builder(),
        home: const TimelinePage(),
      ),
    );
  }
}

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key});
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<dynamic> _posts = [];
  bool _isRecording = false;
  String? _lastLocalPath;
  double _maxAmplitude = -100.0;
  Timer? _amplitudeTimer;

  @override
  void initState() {
    super.initState();
    _fetchTimeline();
  }

  @override
  void dispose() {
    _amplitudeTimer?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- 🛰️ タイムライン取得 ---
  Future<void> _fetchTimeline() async {
    try {
      // 👈 修正：スラッシュが被らないように 'timeline' に変更
      final res = await Amplify.API.get('/timeline').response;
      final List<dynamic> data = jsonDecode(res.decodeBody());
      
      data.sort((a, b) => (b['timestamp'] ?? "").compareTo(a['timestamp'] ?? ""));
      setState(() => _posts = data);
    } catch (e) {
      print("取得エラー: $e");
    }
  }

  // --- 🎙️ 録音開始（Web対応版） ---
  // --- 🎙️ 録音開始（完全Web対応版） ---
  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      
      // 👇 修正ポイント：最初は「空文字」を入れておく（WebはこれでOKになる）
      String path = ''; 
      
      // Webじゃない（Windowsやスマホの）場合だけ、一時フォルダの場所を上書きする
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/roar_temp.m4a';
      }

      _maxAmplitude = -100.0;
      
      // エラーが消えるはずです！
      await _recorder.start(const RecordConfig(), path: path);
      
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        final amp = await _recorder.getAmplitude();
        if (amp.current > _maxAmplitude) _maxAmplitude = amp.current;
      });
      
      setState(() => _isRecording = true);
    }
  }

  // --- 🚀 送信処理 ---
  Future<void> _stopAndUpload() async {
    _amplitudeTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;

    _lastLocalPath = path;

    final key = 'public/roars/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await Amplify.Storage.uploadFile(localFile: AWSFile.fromPath(path), key: key).result;

    final user = await Amplify.Auth.getCurrentUser();
    // 👈 修正：ここも 'roars' に変更
    await Amplify.API.post('/roars', body: HttpPayload.json({
      "userId": user.userId,
      "userName": user.username,
      "s3Key": key,
      "roarPower": _maxAmplitude,
      "message": "サバンナに響け！"
    })).response;

    _fetchTimeline();
  }

  // --- 🔊 再生 ---
  Future<void> _playS3(String key) async {
    final result = await Amplify.Storage.getUrl(key: key).result;
    await _audioPlayer.play(UrlSource(result.url.toString()));
  }

  Future<void> _playLocal() async {
    if (_lastLocalPath != null) {
      // 👈 Web版のBlob URLでも再生できるように UrlSource に統一
      await _audioPlayer.play(UrlSource(_lastLocalPath!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🦁 サバンナ・タイムライン'),
        actions: [
          IconButton(onPressed: _fetchTimeline, icon: const Icon(Icons.refresh)),
          const SignOutButton(),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Row(
              children: [
                Expanded(child: Text(_isRecording ? "全力で吠えろ！" : "最新の声をチェックだガオ！")),
                if (_lastLocalPath != null)
                  IconButton(onPressed: _playLocal, icon: const Icon(Icons.history), tooltip: "直前の録音をローカル再生"),
                FloatingActionButton(
                  onPressed: _isRecording ? _stopAndUpload : _startRecording,
                  backgroundColor: _isRecording ? Colors.red : Colors.orange,
                  child: Icon(_isRecording ? Icons.stop : Icons.mic),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchTimeline,
              child: ListView.builder(
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(post['userName'] ?? '名無しライオン', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(post['timestamp']?.toString().split('T').first ?? ''),
                          Text("Power: ${(post['roarPower'] as num? ?? 0).toStringAsFixed(1)} dB"),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_circle_fill, size: 40, color: Colors.orange),
                        onPressed: () => _playS3(post['s3Key']),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}