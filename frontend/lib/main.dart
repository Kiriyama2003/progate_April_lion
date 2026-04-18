import 'dart:convert';
import 'dart:async';
import 'dart:math' show cos, sin;
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
            brightness: Brightness.dark,
          ),
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

  // アバターURLのキャッシュ
  final Map<String, String> _avatarUrlCache = {};
  
  // 🌟 追加：リアクションのキャッシュと自分のユーザーID
  final Map<String, Map<String, dynamic>> _reactionsCache = {};
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _initUserId(); // 🌟 起動時に自分のIDを取得
    _fetchTimeline();
  }

  // 🌟 追加：自分のユーザーIDを保持しておく関数
  Future<void> _initUserId() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      setState(() => _currentUserId = user.userId);
    } catch (e) {
      print("ユーザー情報取得エラー: $e");
    }
  }

  // S3キーから画像URLを取得してキャッシュに保存
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

  // 時間を「日時分秒」に整形する関数
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

  Future<void> _fetchTimeline() async {
    try {
      final res = await Amplify.API.get('timeline').response;
      final List<dynamic> data = jsonDecode(res.decodeBody());
      data.sort(
        (a, b) => (b['timestamp'] ?? "").compareTo(a['timestamp'] ?? ""),
      );
      setState(() => _posts = data);

      for (var post in data) {
        if (post['avatarS3Key'] != null) {
          _loadAvatarUrl(post['avatarS3Key']);
        }
        // 🌟 追加：各投稿のリアクション情報を取得する
        final postId = post['postId'] as String?;
        if (postId != null) {
          _loadReactions(postId);
        }
      }
    } catch (e) {
      print("取得エラー: $e");
    }
  }

  // 🌟 追加：リアクション取得処理 (API GET /reactions)
  Future<void> _loadReactions(String postId) async {
    if (postId.isEmpty) return;
    try {
      final res = await Amplify.API.get(
        'reactions',
        queryParameters: {'postId': postId},
      ).response;
      final data = jsonDecode(res.decodeBody()) as Map<String, dynamic>;
      setState(() => _reactionsCache[postId] = data);
    } catch (e) {
      print("リアクション取得エラー: $e");
    }
  }

  // 🌟 追加：リアクションの追加・削除処理（爆速UIバージョン！）
  Future<void> _toggleReaction(String postId, String reactionType) async {
    final userId = _currentUserId;
    if (userId == null) return;

    final reactions = _reactionsCache[postId] ?? {};
    final reactionData = reactions[reactionType] as Map<String, dynamic>?;
    
    // 現在のリストとカウントをコピー
    final users = List<String>.from(reactionData?['users'] ?? []);
    var count = reactionData?['count'] as int? ?? 0;
    final hasReacted = users.contains(userId);

    // ==========================================
    // 🦁 1. 通信を待たずに、画面の見た目だけ「即座に」変える！
    // ==========================================
    setState(() {
      if (hasReacted) {
        users.remove(userId);
        count--;
      } else {
        users.add(userId);
        count++;
      }
      // キャッシュを上書きして画面を更新
      _reactionsCache[postId]![reactionType] = {'count': count, 'users': users};
    });

    // ==========================================
    // 🦁 2. その裏で、こっそりAWSにデータを送る
    // ==========================================
    try {
      if (hasReacted) {
        await Amplify.API.delete(
          'reactions',
          queryParameters: {'postId': postId, 'userId': userId, 'reactionType': reactionType},
        ).response;
      } else {
        await Amplify.API.post(
          'reactions',
          body: HttpPayload.json({
            'postId': postId,
            'userId': userId,
            'reactionType': reactionType,
          }),
        ).response;
      }
      // 通信が成功したら、念のため最新データを取得し直す
      await _loadReactions(postId);
    } catch (e) {
      print("リアクションエラー: $e");
      // もし通信エラーになったら、ここで元の色に戻す処理を書いたりします
    }
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
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
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
    await Amplify.Storage.uploadFile(
      localFile: AWSFile.fromPath(path),
      key: key,
    ).result;

    final user = await Amplify.Auth.getCurrentUser();

    final profileRes = await Amplify.API
        .get('profile', queryParameters: {'userId': user.userId})
        .response;
    final profile = jsonDecode(profileRes.decodeBody());
    final currentName = profile['userName'] ?? user.username;

    await Amplify.API
        .post(
          'roars',
          body: HttpPayload.json({
            "userId": user.userId,
            "userName": currentName,
            "s3Key": key,
            "roarPower": _maxAmplitude,
            "message": "サバンナに響け！",
          }),
        )
        .response;

    _fetchTimeline();
  }

  Future<void> _playS3(String key) async {
    final result = await Amplify.Storage.getUrl(key: key).result;
    await _audioPlayer.play(UrlSource(result.url.toString()));
  }

  // 🌟 追加：リアクションボタンのUI作成
  Widget _buildReactionButtons(String postId) {
    final reactions = _reactionsCache[postId] ?? {};
    
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Wrap(
        spacing: 8,
        children: [
          _reactionChip(postId, 'nice', '👍', 'いいね！', reactions),
          _reactionChip(postId, 'wakaru', '💭', 'わかる', reactions),
          _reactionChip(postId, 'sugoi', '🔥', 'すごい', reactions),
          _reactionChip(postId, 'gao', '🦁', 'ガオ！', reactions),
        ],
      ),
    );
  }

  // 🌟 追加：各リアクションボタンのデザインと動作
  Widget _reactionChip(
    String postId,
    String type,
    String emoji,
    String label,
    Map<String, dynamic> reactions,
  ) {
    final data = reactions[type] as Map<String, dynamic>?;
    final count = data?['count'] as int? ?? 0;
    final users = (data?['users'] as List?)?.cast<String>() ?? [];
    final hasReacted = _currentUserId != null && users.contains(_currentUserId);

    return ActionChip(
      avatar: Text(emoji),
      label: Text('$label $count'),
      backgroundColor: hasReacted ? Colors.orange.withOpacity(0.3) : null,
      onPressed: () => _toggleReaction(postId, type),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🦁 タイムライン'),
        actions: [
          IconButton(
            onPressed: _fetchTimeline,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () async {
              final user = await Amplify.Auth.getCurrentUser();
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfilePage(userId: user.userId),
                ),
              );
            },
          ),
          const SignOutButton(),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                color: Theme.of(context).colorScheme.surfaceVariant,
                child: Row(
                  children: [
                    const Expanded(child: Text("最新の声をチェックだガオ！")),
                    FloatingActionButton(
                      onPressed: _isRecording
                          ? _stopAndUpload
                          : _startRecording,
                      backgroundColor: _isRecording
                          ? Colors.red
                          : Colors.orange,
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
                      final avatarS3Key = post['avatarS3Key'] as String?;
                      final avatarUrl = _avatarUrlCache[avatarS3Key];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: InkWell(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    UserProfilePage(userId: post['userId']),
                              ),
                            ),
                            child: CircleAvatar(
                              backgroundImage: avatarUrl != null
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl == null
                                  ? const Icon(Icons.pets)
                                  : null,
                            ),
                          ),
                          title: Text(
                            post['userName'] ?? '名無し',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatTimestamp(post['timestamp']),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                "Power: ${(post['roarPower'] as num? ?? 0).toStringAsFixed(1)} dB",
                              ),
                              if (post['transcript'] != null &&
                                  post['transcript'].isNotEmpty)
                                Text(
                                  "🗣️ 「${post['transcript']}」",
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              if (post['aiAdvice'] != null &&
                                  post['aiAdvice'].isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 5),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: Colors.orange),
                                  ),
                                  child: Text(
                                    "🦁 AI師匠: ${post['aiAdvice']}",
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                    ),
                                  ),
                                ),
                              // 🌟 追加：ここにリアクションボタンを表示する
                              if (post['postId'] != null)
                                _buildReactionButtons(post['postId']),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.play_circle_fill,
                              size: 40,
                              color: Colors.orange,
                            ),
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
          if (_isRecording)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(blurRadius: 10, color: Colors.black),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 1.0, end: 1.15),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeInOut,
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              child: CustomPaint(
                                size: const Size(150, 150),
                                painter: LionPainter(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '叫べ！',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(blurRadius: 15, color: Colors.black),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '録音中...',
                          style: TextStyle(fontSize: 18, color: Colors.white70),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _stopAndUpload,
                          icon: const Icon(Icons.stop),
                          label: const Text('停止して投稿'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ======================================================================
// 🦁 ボスライオンのPainter（叫んでいる姿）
// ======================================================================
class LionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);

    paint.color = const Color(0xFF8B4513);
    for (var angle = 0; angle < 360; angle += 15) {
      final rad = angle * 3.14159 / 180;
      final x = center.dx + 55 * cos(rad);
      final y = center.dy + 50 * sin(rad);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 25, height: 40),
        paint,
      );
    }

    paint.color = const Color(0xFFFFA500);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 80, height: 85),
      paint,
    );

    paint.color = const Color(0xFFFFE4B5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 25),
        width: 50,
        height: 40,
      ),
      paint,
    );

    paint.color = const Color(0xFF8B0000);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 32),
        width: 35,
        height: 25,
      ),
      paint,
    );

    paint.color = const Color(0xFF4A0000);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 35),
        width: 25,
        height: 15,
      ),
      paint,
    );

    paint.color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 10, center.dy + 20),
        width: 6,
        height: 14,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 10, center.dy + 20),
        width: 6,
        height: 14,
      ),
      paint,
    );

    paint.color = const Color(0xFF4A2F00);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 10),
        width: 16,
        height: 12,
      ),
      paint,
    );

    paint.color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx - 20, center.dy - 15),
        width: 24,
        height: 20,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx + 20, center.dy - 15),
        width: 24,
        height: 20,
      ),
      paint,
    );

    paint.color = Colors.black;
    canvas.drawCircle(Offset(center.dx - 20, center.dy - 15), 6, paint);
    canvas.drawCircle(Offset(center.dx + 20, center.dy - 15), 6, paint);

    paint.color = Colors.white;
    canvas.drawCircle(Offset(center.dx - 22, center.dy - 17), 2, paint);
    canvas.drawCircle(Offset(center.dx + 18, center.dy - 17), 2, paint);

    paint.color = const Color(0xFF5C3317);
    paint.strokeWidth = 4;
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - 32, center.dy - 32),
      Offset(center.dx - 10, center.dy - 28),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + 32, center.dy - 32),
      Offset(center.dx + 10, center.dy - 28),
      paint,
    );

    paint.style = PaintingStyle.fill;
    paint.color = const Color(0xFF8B4513);
    canvas.drawCircle(Offset(center.dx - 35, center.dy - 35), 15, paint);
    canvas.drawCircle(Offset(center.dx + 35, center.dy - 35), 15, paint);
    paint.color = const Color(0xFFFFB6C1);
    canvas.drawCircle(Offset(center.dx - 35, center.dy - 35), 8, paint);
    canvas.drawCircle(Offset(center.dx + 35, center.dy - 35), 8, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

      final profRes = await Amplify.API
          .get('profile', queryParameters: {'userId': widget.userId})
          .response;
      _profile = jsonDecode(profRes.decodeBody());

      if (_profile['avatarS3Key'] != null && _profile['avatarS3Key'] != '') {
        final urlResult = await Amplify.Storage.getUrl(
          key: _profile['avatarS3Key'],
        ).result;
        _avatarUrl = urlResult.url.toString();
      }

      final postRes = await Amplify.API
          .get('timeline', queryParameters: {'userId': widget.userId})
          .response;
      final List<dynamic> data = jsonDecode(postRes.decodeBody());
      data.sort(
        (a, b) => (b['timestamp'] ?? "").compareTo(a['timestamp'] ?? ""),
      );
      _userPosts = data;
    } catch (e) {
      print("プロフ取得エラー: $e");
    }
    setState(() => _isLoading = false);
  }

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
    final nameController = TextEditingController(
      text: _profile['userName'] ?? '',
    );
    String newAvatarKey = _profile['avatarS3Key'] ?? '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('プロフィール編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '表示名'),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: const Text('画像を選択'),
              onPressed: () async {
                final picker = ImagePicker();
                final pickedFile = await picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (pickedFile != null) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('画像アップロード中...')));
                  newAvatarKey =
                      'public/avatars/${DateTime.now().millisecondsSinceEpoch}.jpg';
                  await Amplify.Storage.uploadFile(
                    localFile: AWSFile.fromPath(pickedFile.path),
                    key: newAvatarKey,
                  ).result;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('画像アップロード完了！')));
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              await Amplify.API
                  .post(
                    'profile',
                    body: HttpPayload.json({
                      "userId": widget.userId,
                      "userName": nameController.text,
                      "avatarS3Key": newAvatarKey,
                    }),
                  )
                  .response;
              _loadData();
            },
            child: const Text('保存'),
          ),
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
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

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
                  backgroundImage: _avatarUrl != null
                      ? NetworkImage(_avatarUrl!)
                      : null,
                  child: _avatarUrl == null
                      ? const Icon(Icons.person, size: 50)
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  _profile['userName'] ?? '名無しライオン',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_isMe) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('プロフィールを編集'),
                    onPressed: _editProfile,
                  ),
                ],
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
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.mic),
                    title: Text(
                      _formatTimestamp(post['timestamp']),
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      "Power: ${(post['roarPower'] as num? ?? 0).toStringAsFixed(1)} dB",
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.play_circle_fill,
                        size: 40,
                        color: Colors.orange,
                      ),
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