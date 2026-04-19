// lib/pages/timeline_page.dart
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';

import '../utils/format_utils.dart';
import '../widgets/lion_painter.dart';
import 'profile_page.dart';

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
  // main.dart の _TimelinePageState クラス内
  final Map<String, List<dynamic>> _commentsCache = {}; // 🌟 コメント保存用
  final Map<String, TextEditingController> _commentControllers = {}; // 🌟 入力欄管理用
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
          _loadComments(postId); // 🌟 これを追加！
          _commentControllers.putIfAbsent(postId, () => TextEditingController());
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

  // 🌟 追加：コメントを取得する
  Future<void> _loadComments(String postId) async {
    try {
      final res = await Amplify.API.get('comments', queryParameters: {'postId': postId}).response;
      final List<dynamic> data = jsonDecode(res.decodeBody());
      setState(() => _commentsCache[postId] = data);
    } catch (e) {
      print("コメント取得エラー: $e");
    }
  }

  // 🌟 追加：コメントを投稿する
  Future<void> _postComment(String postId) async {
    final controller = _commentControllers[postId];
    if (controller == null || controller.text.isEmpty) return;
    
    final content = controller.text;
    controller.clear(); // 🌟 送信ボタンを押したらすぐ消す！

    try {
      final user = await Amplify.Auth.getCurrentUser();
      await Amplify.API.post('comments', body: HttpPayload.json({
        'postId': postId,
        'userId': user.userId,
        'userName': 'サバンナの仲間', // 🌟 ここは本来プロフから取ると最高
        'content': content,
      })).response;
      
      _loadComments(postId); // 🌟 投稿が終わったらリストを更新
    } catch (e) {
      print("コメント投稿エラー: $e");
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

    final fileName = 'roars/${DateTime.now().millisecondsSinceEpoch}.m4a';
    
    // アップロード
    await Amplify.Storage.uploadFile(
      localFile: AWSFile.fromPath(path),
      key: fileName, 
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
            // 🌟 修正：'public/' を付けず、アップロードした時と同じ key を渡す！
            "s3Key": fileName, 
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
  // 🌟 追加：コメントエリアのUI
  Widget _buildCommentSection(String postId) {
    final comments = _commentsCache[postId] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        ...comments.map((c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Colors.white),
              children: [
                TextSpan(text: "${c['userName']}: ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                TextSpan(text: c['content']),
              ],
            ),
          ),
        )),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _commentControllers[postId],
                decoration: const InputDecoration(hintText: 'コメント...', isDense: true),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, size: 20, color: Colors.orange),
              onPressed: () => _postComment(postId),
            ),
          ],
        ),
      ],
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
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfilePage(userId: user.userId),
                  ),
              );
              if (mounted) {
                _fetchTimeline();
              }
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
                            onTap: () async{
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      UserProfilePage(userId: post['userId']),
                                ),
                              );
                              if (mounted) {
                                _fetchTimeline();
                              }
                            },
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
                          // main.dart の 290行目付近にある subtitle: Column(...) の中身
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatTimestamp(post['timestamp']),
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              Text(
                                "Power: ${(post['roarPower'] as num? ?? 0).toStringAsFixed(1)} dB",
                              ),
                              
                              // 🌟 修正：文字起こしテキストを大きく・太字にする！
                              if (post['transcript'] != null && post['transcript'].isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                                  child: Text(
                                    "🗣️ 「${post['transcript']}」",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22, // 👈 以前よりかなり大きくしました
                                      fontWeight: FontWeight.bold, // 👈 太字で強調！
                                    ),
                                  ),
                                ),

                              if (post['aiAdvice'] != null && post['aiAdvice'].isNotEmpty)
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
                                    style: const TextStyle(color: Colors.orangeAccent),
                                  ),
                                ),
                                
                              // 🌟 既存のリアクションボタン
                              if (post['postId'] != null)
                                _buildReactionButtons(post['postId']),
                                
                              // 🌟 追加：コメントセクションを表示する（ここが手順5のメイン！）
                              if (post['postId'] != null)
                                _buildCommentSection(post['postId']),
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

