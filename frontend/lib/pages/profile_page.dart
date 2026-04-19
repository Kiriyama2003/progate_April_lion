import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/format_utils.dart'; // インポート

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

  // 🌟 キャリブレーション実行用の関数
  Future<void> _redoCalibration() async {
    final recorder = AudioRecorder(); // その場でレコーダー召喚！
    
    if (await recorder.hasPermission()) {
      // 画面に「測定中...」と出すための簡易ダイアログ
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.orange),
              SizedBox(height: 20),
              Text("3秒間、普通の声を出してくれガオ！🦁"),
            ],
          ),
        ),
      );

      double tempMax = -100.0;
      await recorder.start(const RecordConfig(), path: ''); // Web/Mobile両対応

      // 3秒間サンプリング
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        final amp = await recorder.getAmplitude();
        if (amp.current > tempMax) tempMax = amp.current;
      }

      await recorder.stop();
      
      // 記憶の上書き！
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('basePower', tempMax);

      if (mounted) {
        Navigator.pop(context); // ダイアログを閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("基準パワーを ${tempMax.toStringAsFixed(1)} dB に更新したぜ！🔥")),
        );
      }
    }
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
                if (_isMe) ...[
                  // 既存の編集ボタン
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('プロフィールを編集'),
                    onPressed: _editProfile,
                  ),
                  const SizedBox(height: 8), // 少しスキマを開ける
                  // 🌟 追加：キャリブレーションやり直しボタン
                  OutlinedButton.icon(
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('「最初の儀式」をやり直す'),
                    onPressed: _redoCalibration, // さっき作った関数を呼ぶ！
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                    ),
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

