import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LionEmotion { angry, sad, tired, neutral }

class RoarPost {
  final String text;
  final double volume;
  final LionEmotion emotion;
  final String? leaderReply;

  RoarPost({
    required this.text,
    required this.volume,
    required this.emotion,
    this.leaderReply,
  });
}

// 掲示板の状態を管理するプロバイダー
final roarProvider = StateNotifierProvider<RoarNotifier, List<RoarPost>>((ref) {
  return RoarNotifier();
});

class RoarNotifier extends StateNotifier<List<RoarPost>> {
  RoarNotifier() : super([]);

  void addPost(RoarPost post) {
    state = [post, ...state]; // 新しい投稿を上に追加
  }

  void updateWithReply(int index, String reply) {
    final newList = [...state];
    final old = newList[index];
    newList[index] = RoarPost(
      text: old.text,
      volume: old.volume,
      emotion: old.emotion,
      leaderReply: reply,
    );
    state = newList;
  }
}