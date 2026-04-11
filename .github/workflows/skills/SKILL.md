🦁 プロジェクト：ガオガオ・サバンナ
📋 プロダクト概要
ストレス社会というサバンナで戦う「若きライオン（ユーザー）」たちのための、音声感情解析型・匿名掲示板。叫びを「咆哮」に変え、群れのリーダーAIが全肯定で励ますメンタルケア・プラットフォーム。

🏗️ 技術スタック
Frontend: Flutter (Riverpod, record, noise_meter)

Backend: AWS (Amplify, AppSync, S3, Lambda)

AI: Amazon Transcribe, Amazon Comprehend, Bedrock (Claude 3) / Gemini API

📊 データモデル (ER図)
VSCodeの「Markdown Preview Mermaid Support」拡張機能を入れると、エディタ上で図として表示されます。

コード スニペット
erDiagram
    USER ||--o{ POST : "bellows (叫ぶ)"
    POST ||--o| LEADER_REPLY : "triggers (解析・返信)"
    
    USER {
        string user_id PK "Cognito ID"
        string nickname "名無しのライオン#xxxx"
    }

    POST {
        string post_id PK "UUID"
        string user_id FK "投稿者ID"
        string raw_text "文字起こしテキスト"
        float volume_level "最大デシベル値"
        string emotion_tag "angry | sad | tired | neutral"
        datetime created_at "投稿日時"
    }

    LEADER_REPLY {
        string reply_id PK "UUID"
        string post_id FK "投稿ID"
        string message "リーダーからの励まし文"
        datetime created_at "返信日時"
    }
🛠️ 機能仕様
1. 咆哮（音声投稿）機能
音声認識: recordパッケージで録音。

感情解析: - 物理: noise_meter でデシベルを取得（Flutter）。

論理: Amazon Transcribe + Comprehend で内容を解析（AWS）。

ビジュアル: 音量に連動してライオンが振動するアニメーション。

2. サバンナ掲示板（タイムライン）
リアルタイム同期: AWS AppSync (GraphQL Subscription) を使用。

感情アイコン: 解析結果に基づき、ライオンの表情（怒り・悲しみ等）を切り替え。

通知: 新着投稿時に「ガオー！」（咆哮音）を再生。

3. リーダーAI「キング・レオ」
役割: 投稿を全肯定し、サバンナの掟に基づいたアドバイスを生成。

ロジック: Lambda関数内でBedrock/Geminiを呼び出し、返信をDBへ自動書き込み。

🚀 実装ロードマップ
[ ] Phase 1: UIモック作成（LINE風タイムライン・叫ぶボタン）

[ ] Phase 2: ローカルでの音声録音 & 音量検知ロジック

[ ] Phase 3: Amplify初期化 & S3アップロード実装

[ ] Phase 4: AWS AIパイプライン（解析〜返信生成）の結合

[ ] Phase 5: 咆哮SEの追加 & デザインの最終調整
https://www.notion.so/33fa9f15b56880f198e8f3e2844a743a?source=copy_link