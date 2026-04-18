import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';

import 'amplifyconfiguration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureAmplify();
  runApp(const MyApp());
}

Future<void> _configureAmplify() async {
  try {
    await Amplify.addPlugins([AmplifyAuthCognito(), AmplifyAPI(), AmplifyStorageS3()]);
    await Amplify.configure(amplifyconfig);
  } catch (e) { print('初期化エラー: $e'); }
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

// ======================================================================
// 🦁 1. メインのタイムライン画面
// ======================================================================
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
  double _maxAmplitude = -100.0;
  Timer? _amplitudeTimer;

  // 🌟 追加：アバターURLのキャッシュ
  final Map<String, String> _avatarUrlCache = {};

  @override
  void initState() {
    super.initState();
    _fetchTimeline();
  }

  // 🌟 追加：S3キーから画像URLを取得してキャッシュに保存
  Future<void> _loadAvatarUrl(String s3Key) async {
    if (s3Key.isEmpty || _avatarUrlCache.containsKey(s3Key)) return;
    try {
      final result = await Amplify.Storage.getUrl(key: s3Key).result;
      setState(() {
        _avatarUrlCache[s3Key] = result.url.toString();
      });
    } catch (e) {
      print("アバター取得失敗: $e");
    }
  }

  // 🌟 追加：時間を「日時分秒」に整形する関数
  String _formatTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      // タイムスタンプをローカル時間（日本時間など）に変換
      final dateTime = DateTime.parse(timestamp).toLocal();
      final year = dateTime.year;
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final second = dateTime.second.toString().padLeft(2, '0');
      return '$year/$month/$day $hour:$minute:$second';
    } catch (e) {
      return timestamp;
    }
  }

  Future<void> _fetchTimeline() async {
    try {
      final res = await Amplify.API.get('timeline').response;
      final List<dynamic> data = jsonDecode(res.decodeBody());
      data.sort((a, b) => (b['timestamp'] ?? "").compareTo(a['timestamp'] ?? ""));
      setState(() => _posts = data);

      // 🌟 追加：投稿データ取得後、各投稿者のアバターURLを読み込む
      for (var post in data) {
        if (post['avatarS3Key'] != null) {
          _loadAvatarUrl(post['avatarS3Key']);
        }
      }
    } catch (e) { print("取得エラー: $e"); }
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/roar_temp.m4a';
      }
      _maxAmplitude = -100.0;
      await _recorder.start(const RecordConfig(), path: path);
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        final amp = await _recorder.getAmplitude();
        if (amp.current > _maxAmplitude) _maxAmplitude = amp.current;
      });
      setState(() => _isRecording = true);
    }
  }

  Future<void> _stopAndUpload() async {
    _amplitudeTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;

    final key = 'public/roars/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await Amplify.Storage.uploadFile(localFile: AWSFile.fromPath(path), key: key).result;

    final user = await Amplify.Auth.getCurrentUser();
    
    // プロフィール情報を取得して投稿に名前を乗せる
    final profileRes = await Amplify.API.get('profile', queryParameters: {'userId': user.userId}).response;
    final profile = jsonDecode(profileRes.decodeBody());
    final currentName = profile['userName'] ?? user.username;

    await Amplify.API.post('roars', body: HttpPayload.json({
      "userId": user.userId,
      "userName": currentName,
      "s3Key": key,
      "roarPower": _maxAmplitude,
      "message": "サバンナに響け！"
    })).response;

    _fetchTimeline();
  }

  Future<void> _playS3(String key) async {
    final result = await Amplify.Storage.getUrl(key: key).result;
    await _audioPlayer.play(UrlSource(result.url.toString()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🦁 タイムライン'),
        actions: [
          IconButton(onPressed: _fetchTimeline, icon: const Icon(Icons.refresh)),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () async {
              final user = await Amplify.Auth.getCurrentUser();
              if (!mounted) return;
              Navigator.push(context, MaterialPageRoute(builder: (context) => UserProfilePage(userId: user.userId)));
            },
          ),
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
                const Expanded(child: Text("最新の声をチェックだガオ！")),
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
                  // 🌟 追加：キャッシュから画像URLを取り出す
                  final avatarS3Key = post['avatarS3Key'] as String?;
                  final avatarUrl = _avatarUrlCache[avatarS3Key];

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      // 🌟 修正：画像を表示するように変更
                      leading: InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => UserProfilePage(userId: post['userId']))),
                        child: CircleAvatar(
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null ? const Icon(Icons.pets) : null,
                        ),
                      ),
                      title: Text(post['userName'] ?? '名無し', style: const TextStyle(fontWeight: FontWeight.bold)),
                      // 🌟 修正：日時分秒の表示を適用
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_formatTimestamp(post['timestamp']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
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

// ======================================================================
// 👑 2. ユーザープロフィール画面（Twitter風）
// ======================================================================
class UserProfilePage extends StatefulWidget {
  final String userId;
  const UserProfilePage({super.key, required this.userId});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<dynamic> _userPosts = [];
  Map<String, dynamic> _profile = {};
  String? _avatarUrl;
  bool _isMe = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final currentUser = await Amplify.Auth.getCurrentUser();
      _isMe = currentUser.userId == widget.userId;

      final profRes = await Amplify.API.get('profile', queryParameters: {'userId': widget.userId}).response;
      _profile = jsonDecode(profRes.decodeBody());

      if (_profile['avatarS3Key'] != null && _profile['avatarS3Key'] != '') {
        final urlResult = await Amplify.Storage.getUrl(key: _profile['avatarS3Key']).result;
        _avatarUrl = urlResult.url.toString();
      }

      final postRes = await Amplify.API.get('timeline', queryParameters: {'userId': widget.userId}).response;
      final List<dynamic> data = jsonDecode(postRes.decodeBody());
      data.sort((a, b) => (b['timestamp'] ?? "").compareTo(a['timestamp'] ?? ""));
      _userPosts = data;

    } catch (e) {
      print("プロフ取得エラー: $e");
    }
    setState(() => _isLoading = false);
  }

  // 🌟 追加：時間を「日時分秒」に整形する関数（プロフィール画面の投稿一覧用）
  String _formatTimestamp(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      final dateTime = DateTime.parse(timestamp).toLocal();
      final year = dateTime.year;
      final month = dateTime.month.toString().padLeft(2, '0');
      final day = dateTime.day.toString().padLeft(2, '0');
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final second = dateTime.second.toString().padLeft(2, '0');
      return '$year/$month/$day $hour:$minute:$second';
    } catch (e) {
      return timestamp;
    }
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _profile['userName'] ?? '');
    String newAvatarKey = _profile['avatarS3Key'] ?? '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('プロフィール編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '表示名')),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('画像を選択'),
              onPressed: () async {
                final picker = ImagePicker();
                final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                if (pickedFile != null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像アップロード中...')));
                  newAvatarKey = 'public/avatars/${DateTime.now().millisecondsSinceEpoch}.jpg';
                  await Amplify.Storage.uploadFile(localFile: AWSFile.fromPath(pickedFile.path), key: newAvatarKey).result;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画像アップロード完了！')));
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              await Amplify.API.post('profile', body: HttpPayload.json({
                "userId": widget.userId,
                "userName": nameController.text,
                "avatarS3Key": newAvatarKey,
              })).response;
              _loadData();
            },
            child: const Text('保存'),
          )
        ],
      ),
    );
  }

  Future<void> _playS3(String key) async {
    final result = await Amplify.Storage.getUrl(key: key).result;
    await _audioPlayer.play(UrlSource(result.url.toString()));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: Text('${_profile['userName'] ?? '名無し'}のページ')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.black26,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                  child: _avatarUrl == null ? const Icon(Icons.person, size: 50) : null,
                ),
                const SizedBox(height: 10),
                Text(_profile['userName'] ?? '名無しライオン', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                if (_isMe) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('プロフィールを編集'),
                    onPressed: _editProfile,
                  )
                ]
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _userPosts.length,
              itemBuilder: (context, index) {
                final post = _userPosts[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    leading: const Icon(Icons.mic),
                    // 🌟 修正：プロフィール画面の過去の投稿一覧にもフォーマットした時間を適用
                    title: Text(_formatTimestamp(post['timestamp']), style: const TextStyle(fontSize: 14)),
                    subtitle: Text("Power: ${(post['roarPower'] as num? ?? 0).toStringAsFixed(1)} dB"),
                    trailing: IconButton(
                      icon: const Icon(Icons.play_circle_fill, size: 40, color: Colors.orange),
                      onPressed: () => _playS3(post['s3Key']),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}