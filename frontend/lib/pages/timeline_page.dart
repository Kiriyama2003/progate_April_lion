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
import 'package:shared_preferences/shared_preferences.dart'; // 🌟 追加：記憶用

import '../utils/format_utils.dart';
import '../widgets/lion_painter.dart';
import '../widgets/roar_loading_overlay.dart';
import 'profile_page.dart';

// 🌟 並び替えのモードを定義
enum SortMode { latest, popular, power }

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

  // 15秒制限とカウントダウン用の変数
  Timer? _maxRecordTimer;
  Timer? _countdownTimer;
  int _remainingSeconds = 15;

  bool _isProcessing = false;
  Timer? _timeoutTimer;

  // 現在の並び替えモード（初期値は「最新」）
  SortMode _currentSortMode = SortMode.latest;

  final Map<String, String> _avatarUrlCache = {};
  final Map<String, Map<String, dynamic>> _reactionsCache = {};
  final Map<String, List<dynamic>> _commentsCache = {};
  final Map<String, TextEditingController> _commentControllers = {};
  String? _currentUserId;

  // 🌟 追加：キャリブレーション（基準値）用の変数
  double? _basePower;
  bool _isCalibrating = false;

  @override
  void initState() {
    super.initState();
    _initUserId();
    _fetchTimeline();
    _checkCalibration(); // 🌟 追加：起動時にキャリブレーションを確認
  }

  // 🌟 追加：初回起動かどうかのチェック
  Future<void> _checkCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBase = prefs.getDouble('basePower');
    
    if (savedBase == null) {
      // 基準値がない（初回）場合は、画面が描画された直後にダイアログを出す
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCalibrationDialog();
      });
    } else {
      // すでに基準値があれば変数にセット
      setState(() {
        _basePower = savedBase;
      });
    }
  }

  // 🌟 追加：キャリブレーション用のダイアログ
  Future<void> _showCalibrationDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false, // 測定が終わるまで閉じられないようにする
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('🦁 最初の儀式'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'マイク性能の差をなくし、公平なサバンナを作るぜ！\n\n'
                    '「あー」と普段の会話くらいの声を出したまま、下のボタンを押してくれガオ！',
                  ),
                  const SizedBox(height: 20),
                  if (_isCalibrating)
                    const Column(
                      children: [
                        CircularProgressIndicator(color: Colors.orange),
                        SizedBox(height: 10),
                        Text('3秒間 測定中だガオ...'),
                      ],
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () async {
                        setStateDialog(() => _isCalibrating = true);
                        await _runCalibration();
                        if (context.mounted) {
                          Navigator.of(context).pop(); // 測定が終わったら閉じる
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('測定完了！基準パワーは ${_basePower!.toStringAsFixed(1)} dB だぜ！'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.mic),
                      label: const Text('測定開始 (3秒)'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    ),
                ],
              ),
            );
          }
        );
      }
    );
  }

  // 🌟 追加：3秒間だけ録音して基準値を保存する処理
  Future<void> _runCalibration() async {
    if (await _recorder.hasPermission()) {
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/calib_temp.m4a';
      }
      double tempMax = -100.0;
      await _recorder.start(const RecordConfig(), path: path);
      
      final timer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        final amp = await _recorder.getAmplitude();
        if (amp.current > tempMax) tempMax = amp.current;
      });

      await Future.delayed(const Duration(seconds: 3)); // 3秒待つ
      
      timer.cancel();
      await _recorder.stop();

      // 測定した基準値をスマホに記憶させる
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('basePower', tempMax);
      
      if (mounted) {
        setState(() {
          _basePower = tempMax;
          _isCalibrating = false;
        });
      }
    }
  }

  Future<void> _initUserId() async {
    try {
      final user = await Amplify.Auth.getCurrentUser();
      if (mounted) {
        setState(() => _currentUserId = user.userId);
      }
    } catch (e) {
      print("ユーザー情報取得エラー: $e");
    }
  }

  Future<void> _loadAvatarUrl(String s3Key) async {
    if (s3Key.isEmpty || _avatarUrlCache.containsKey(s3Key)) return;
    try {
      final result = await Amplify.Storage.getUrl(key: s3Key).result;
      if (mounted) {
        setState(() {
          _avatarUrlCache[s3Key] = result.url.toString();
        });
      }
    } catch (e) {
      print("アバター取得失敗: $e");
    }
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

  // リストを並び替える専用の関数
  void _applySorting() {
    setState(() {
      if (_currentSortMode == SortMode.latest) {
        _posts.sort((a, b) => (b['timestamp'] ?? "").compareTo(a['timestamp'] ?? ""));
      } else if (_currentSortMode == SortMode.popular) {
        _posts.sort((a, b) => (b['totalReactions'] as num? ?? 0).compareTo(a['totalReactions'] as num? ?? 0));
      } else if (_currentSortMode == SortMode.power) {
        _posts.sort((a, b) => (b['roarPower'] as num? ?? -100).compareTo(a['roarPower'] as num? ?? -100));
      }
    });
  }

  Future<void> _fetchTimeline() async {
    try {
      final res = await Amplify.API.get('timeline').response;
      final List<dynamic> data = jsonDecode(res.decodeBody());
      
      if (mounted) {
        setState(() => _posts = data);
        _applySorting(); 
      }

      for (var post in data) {
        if (post['avatarS3Key'] != null) {
          _loadAvatarUrl(post['avatarS3Key']);
        }
        final postId = post['postId'] as String?;
        if (postId != null) {
          _loadReactions(postId);
          _loadComments(postId);
          _commentControllers.putIfAbsent(postId, () => TextEditingController());
        }
      }
    } catch (e) {
      print("取得エラー: $e");
    }
  }

  Future<void> _loadReactions(String postId) async {
    if (postId.isEmpty) return;
    try {
      final res = await Amplify.API.get(
        'reactions',
        queryParameters: {'postId': postId},
      ).response;
      final data = jsonDecode(res.decodeBody()) as Map<String, dynamic>;
      if (mounted) {
        setState(() => _reactionsCache[postId] = data);
      }
    } catch (e) {
      print("リアクション取得エラー: $e");
    }
  }

  Future<void> _loadComments(String postId) async {
    try {
      final res = await Amplify.API.get('comments', queryParameters: {'postId': postId}).response;
      final List<dynamic> data = jsonDecode(res.decodeBody());
      if (mounted) {
        setState(() => _commentsCache[postId] = data);
      }
    } catch (e) {
      print("コメント取得エラー: $e");
    }
  }

  Future<void> _postComment(String postId) async {
    final controller = _commentControllers[postId];
    if (controller == null || controller.text.isEmpty) return;
    
    final content = controller.text;
    controller.clear(); 

    try {
      final user = await Amplify.Auth.getCurrentUser();
      await Amplify.API.post('comments', body: HttpPayload.json({
        'postId': postId,
        'userId': user.userId,
        'userName': 'サバンナの仲間', 
        'content': content,
      })).response;
      
      _loadComments(postId); 
    } catch (e) {
      print("コメント投稿エラー: $e");
    }
  }

  Future<void> _toggleReaction(String postId, String reactionType) async {
    final userId = _currentUserId;
    if (userId == null) return;

    final reactions = _reactionsCache[postId] ?? {};
    final reactionData = reactions[reactionType] as Map<String, dynamic>?;
    
    final users = List<String>.from(reactionData?['users'] ?? []);
    var count = reactionData?['count'] as int? ?? 0;
    final hasReacted = users.contains(userId);

    if (mounted) {
      setState(() {
        if (hasReacted) {
          users.remove(userId);
          count--;
        } else {
          users.add(userId);
          count++;
        }
        _reactionsCache[postId]![reactionType] = {'count': count, 'users': users};
      });
    }

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
      await _fetchTimeline();
    } catch (e) {
      print("リアクションエラー: $e");
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
      _remainingSeconds = 15; 
      
      await _recorder.start(const RecordConfig(), path: path);
      
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        final amp = await _recorder.getAmplitude();
        if (amp.current > _maxAmplitude) _maxAmplitude = amp.current;
      });

      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _remainingSeconds > 0) {
          setState(() => _remainingSeconds--);
        }
      });

      if (mounted) {
        setState(() => _isRecording = true);
      }

      _maxRecordTimer = Timer(const Duration(seconds: 15), () {
        if (_isRecording) {
          _stopAndUpload();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('熱意は伝わったぜ！15秒で自動投稿したガオ！🔥'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      });
    }
  }

  Future<void> _stopAndUpload() async {
    _amplitudeTimer?.cancel();
    _maxRecordTimer?.cancel();
    _countdownTimer?.cancel();
    
    final path = await _recorder.stop();
    if (mounted) {
      setState(() => _isRecording = false);
    }
    if (path == null) return;

    if (mounted) {
      setState(() => _isProcessing = true);
    }

    _timeoutTimer = Timer(const Duration(minutes: 1), () {
      if (_isProcessing) {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
        print("タイムアウトで修行中断だガオ！");
      }
    });

    try {
      final fileName = 'roars/${DateTime.now().millisecondsSinceEpoch}.m4a';
      
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

      // 🌟 ここが最大の魔法！「真のパワー（伸び幅）」を計算する
      double finalPower = _maxAmplitude - (_basePower ?? -50.0);

      await Amplify.API
          .post(
            'roars',
            body: HttpPayload.json({
              "userId": user.userId,
              "userName": currentName,
              "s3Key": fileName, 
              "roarPower": finalPower, // 🌟 真のパワーをAWSに送る！
              "message": "サバンナに響け！",
            }),
          )
          .response;

      await _fetchTimeline();
    } catch (e) {
      print("投稿エラー: $e");
    } finally {
      _timeoutTimer?.cancel();
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _playS3(String key) async {
    final result = await Amplify.Storage.getUrl(key: key).result;
    await _audioPlayer.play(UrlSource(result.url.toString()));
  }

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
        title: const Text('🦁 ガオガオ サバンナ'),
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
                _checkCalibration();
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: SegmentedButton<SortMode>(
                  segments: const [
                    ButtonSegment<SortMode>(value: SortMode.latest, label: Text('最新 🕒')),
                    ButtonSegment<SortMode>(value: SortMode.popular, label: Text('人気 🔥')),
                    ButtonSegment<SortMode>(value: SortMode.power, label: Text('パワー 📢')),
                  ],
                  selected: {_currentSortMode},
                  onSelectionChanged: (Set<SortMode> newSelection) {
                    setState(() {
                      _currentSortMode = newSelection.first;
                    });
                    _applySorting(); 
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color>(
                      (Set<WidgetState> states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.orange.withOpacity(0.4);
                        }
                        return Colors.transparent;
                      },
                    ),
                  ),
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

                      // 🌟 Cardの中身を ListTile から「Padding + Column」に変更するぜ！
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0), // カード内の余白を作る
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. 【ここがポイント！】アバターと名前情報を横並びにする
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center, // 垂直方向の真ん中に揃える
                                children: [
                                  // 🌟 アバター
                                  InkWell(
                                    onTap: () async {
                                      // 🌟 相手のユーザーIDを使ってプロフィール画面へジャンプ！
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => UserProfilePage(userId: post['userId']),
                                        ),
                                      );
                                      // プロフィールから戻ってきたらタイムラインを更新する
                                      if (mounted) {
                                        _fetchTimeline();
                                        _checkCalibration();
                                      }
                                    },
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                                      child: avatarUrl == null ? const Icon(Icons.pets) : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12), // アバターと名前の間のスキマ
                                  // 🌟 名前・時間・Power を縦に並べる
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          post['userName'] ?? '名無し',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        Text(
                                          _formatTimestamp(post['timestamp']),
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                        Text(
                                          "Power: ${(post['roarPower'] as num? ?? 0) > 0 ? '+' : ''}${(post['roarPower'] as num? ?? 0).toStringAsFixed(1)} dB",
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 🌟 再生ボタンを右端に配置
                                  IconButton(
                                    icon: const Icon(Icons.play_circle_fill, size: 36, color: Colors.orange),
                                    onPressed: () => _playS3(post['s3Key']),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 10), // ヘッダーと本文の間のスキマ

                              // 2. 叫び声の内容（本文）
                              if (post['transcript'] != null && post['transcript'].isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text(
                                    "🗣️ 「${post['transcript']}」",
                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                ),

                              // 3. AI師匠のアドバイス
                              if (post['aiAdvice'] != null && post['aiAdvice'].isNotEmpty)
                                Container(
                                  width: double.infinity, // 横幅いっぱい
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.orange.withOpacity(0.5)),
                                  ),
                                  child: Text(
                                    "🦁 AI師匠: ${post['aiAdvice']}",
                                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 14),
                                  ),
                                ),
                                
                              // 4. リアクションとコメント（既存の関数を呼ぶ）
                              if (post['postId'] != null) _buildReactionButtons(post['postId']),
                              if (post['postId'] != null) _buildCommentSection(post['postId']),
                            ],
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
                        
                        Text(
                          '残り $_remainingSeconds 秒',
                          style: const TextStyle(
                            fontSize: 24, 
                            fontWeight: FontWeight.bold, 
                            color: Colors.white
                          ),
                        ),
                        const SizedBox(height: 10),
                        
                        SizedBox(
                          width: 200,
                          child: LinearProgressIndicator(
                            value: _remainingSeconds / 15,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
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
          if (_isProcessing)
            RoarLoadingOverlay(
              message: "ライオン師匠が\nアドバイスをひねり出し中...",
              onCancel: () {
                _timeoutTimer?.cancel();
                setState(() => _isProcessing = false);
              },
            ),
        ],
      ),
    );
  }
}