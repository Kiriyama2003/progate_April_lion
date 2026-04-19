# Gao Gao Savannah（ガオガオサバンナ）

音声で「ガオ！」と吠えると、熱血ライオンが AI でアドバイスしてくれる Web アプリです。

## 特徴

- 音声入力 → 文字起こし → AI（Bedrock/Claude 3 Haiku）による熱血ライオンのアドバイス生成
- 投稿タイムライン、プロフィール管理、リアクション・コメント機能
- フロントエンドは Flutter Web、バックエンドは AWS SAM（Lambda + DynamoDB + S3 + Cognito）

## アーキテクチャ

```
[Flutter Web Frontend]
        │
        ▼ (Amplify Auth / API / Storage)
[AWS Backend (SAM)]
  └─ Lambda (Python 3.11)
      ├─ Amazon Bedrock (Claude 3 Haiku) → AIアドバイス生成
      ├─ Amazon Transcribe → 音声→文字起こし
      ├─ DynamoDB (投稿/ユーザー/リアクション/コメント)
      └─ S3 (音声ファイル保存)
```

## プロジェクト構成

```
.
├── backend/                # AWS SAM バックエンド
│   ├── roar_function/      # Lambda 関数（Python）
│   │   ├── app.py          # メインハンドラ（API Gateway 連携）
│   │   └── requirements.txt
│   ├── samconfig.toml
│   └── template.yml        # SAM テンプレート（S3/DynamoDB/Cognito 定義）
│
├── frontend/               # Flutter Web フロントエンド
│   ├── lib/                # ダートソースコード
│   ├── web/                # Webビルド出力
│   └── pubspec.yaml
│
├── amplify.yml             # AWS Amplify Hosting ビルド設定
├── .gitignore
└── README.md
```

## 機能一覧

| エンドポイント | メソッド | 説明 |
|---|---|---|
| `/roars` | POST | 音声投稿（文字起こし + AIアドバイス生成） |
| `/timeline` | GET | 投稿タイムライン取得 |
| `/profile` | POST/GET | プロフィール更新・取得 |
| `/reactions` | POST/GET/DELETE | リアクション追加・一覧・削除 |
| `/comments` | POST/GET | コメント投稿・取得 |

## 主要技術スタック

| 区分 | 技術 |
|---|---|
| **Frontend** | Flutter (SDK 3.11.4), Dart |
| **Backend** | Python 3.11, AWS SAM |
| **AI** | Amazon Bedrock (Claude 3 Haiku) |
| **音声** | Amazon Transcribe |
| **DB** | Amazon DynamoDB |
| **ストレージ** | Amazon S3 |
| **認証** | Amazon Cognito |
| **デプロイ** | AWS Amplify Hosting, `flutter build web` |

## 環境構築

### バックエンド（SAM）

```bash
cd backend
sam build
sam deploy --guided
```

### フロントエンド（Flutter Web）

```bash
cd frontend
flutter pub get
flutter build web
```

### Amplify Hosting

`amplify.yml` にて Flutter Web ビルドの設定がされており、Amplify Console に接続することで自動デプロイが可能です。build 成果物は `build/web` ディレクトリに出力されます。
