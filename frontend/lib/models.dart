import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LionEmotion { angry, sad, tired, neutral }

class Comment {
  final String text;
  final DateTime createdAt;

  Comment({required this.text, required this.createdAt});
}

class RoarPost {
  final String text;
  final double volume;
  final LionEmotion emotion;
  final String? leaderReply;
  final int likes;
  final List<Comment> comments;
  final DateTime createdAt;

  RoarPost({
    required this.text,
    required this.volume,
    required this.emotion,
    this.leaderReply,
    this.likes = 0,
    this.comments = const [],
    required this.createdAt,
  });

  RoarPost copyWith({
    String? text,
    double? volume,
    LionEmotion? emotion,
    String? leaderReply,
    int? likes,
    List<Comment>? comments,
    DateTime? createdAt,
  }) {
    return RoarPost(
      text: text ?? this.text,
      volume: volume ?? this.volume,
      emotion: emotion ?? this.emotion,
      leaderReply: leaderReply ?? this.leaderReply,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      createdAt: createdAt ?? this.createdAt,
    );
  }
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
    newList[index] = old.copyWith(leaderReply: reply);
    state = newList;
  }

  void likePost(int index) {
    final newList = [...state];
    final old = newList[index];
    newList[index] = old.copyWith(likes: old.likes + 1);
    state = newList;
  }

  void addComment(int index, String comment) {
    final newList = [...state];
    final old = newList[index];
    newList[index] = old.copyWith(comments: [...old.comments, Comment(text: comment, createdAt: DateTime.now())]);
    state = newList;
  }
}