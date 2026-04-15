import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

// 別途作成する設定ファイル
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
  } catch (e) { print(e); }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return Authenticator(
      child: MaterialApp(
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
  bool _isRecording = false;

  // 1. 録音 & S3アップロード & API通信を一括実行
  Future<void> _startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/roar.m4a';
    
    if (await _recorder.hasPermission()) {
      await _recorder.start(const RecordConfig(), path: path);
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopAndUpload() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;

    // 1. S3アップロード（path ではなく key を使います）
    final s3Key = 'public/roars/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await Amplify.Storage.uploadFile(
      localFile: AWSFile.fromPath(path),
      key: s3Key, // ← ここを path: StoragePath... から key: s3Key に変更！
    ).result; // 最新版は .result を待つ必要があります

    // 2. API POST（RestOptionsがなくなり、かなりスッキリ書けるようになりました！）
    final user = await Amplify.Auth.getCurrentUser();
    final operation = Amplify.API.post(
      '/roars',
      body: HttpPayload.json({
        "userId": user.userId,
        "s3Key": s3Key,
        "volume": 85.0, // 仮の値
      }),
    );
    await operation.response;

    // 3. 画面にスナックバーを出す（contextの赤線を消すためのおまじないを追加）
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('送信完了だガオ！')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('デバッグ画面')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _isRecording ? _stopAndUpload : _startRecording,
              child: Text(_isRecording ? '止めて送信' : '吠える（録音開始）'),
            ),
            ElevatedButton(
              onPressed: () async {
                // RestOptionsがなくなり、直接パスを書くだけになりました！
                final operation = Amplify.API.get('/timeline');
                final res = await operation.response;
                print(res.decodeBody()); // .body ではなく .decodeBody() を使います
              },
              child: const Text('ログにタイムライン出力'),
            ),
            const SignOutButton(),
          ],
        ),
      ),
    );
  }
}