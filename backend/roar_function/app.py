import json
import boto3
import os
import uuid
import time
import urllib.request
from datetime import datetime
import decimal
from boto3.dynamodb.conditions import Attr

# 🌟 修正：region_name を 'us-east-1' に変更する！
bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, decimal.Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

TABLE_NAME = os.environ.get('TABLE_NAME')
USER_TABLE_NAME = os.environ.get('USER_TABLE_NAME')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
REACTION_TABLE_NAME = os.environ.get('REACTION_TABLE_NAME') # 👈 追加

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)
user_table = dynamodb.Table(USER_TABLE_NAME)
reaction_table = dynamodb.Table(REACTION_TABLE_NAME) # 👈 追加

# AI関連のクライアント
transcribe = boto3.client('transcribe')
bedrock = boto3.client('bedrock-runtime', region_name='ap-northeast-1')

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': '*'
}

# --- 🎙️ 1. 文字起こし関数（詳細デバッグ版） ---
def transcribe_audio(s3_key):
    job_name = f"roar_transcribe_{uuid.uuid4()}"
    job_uri = f"s3://{BUCKET_NAME}/{s3_key}"
    
    print(f"[DEBUG 1] 文字起こし開始: job={job_name}, uri={job_uri}")
    
    try:
        # ジョブの登録
        response = transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            Media={'MediaFileUri': job_uri},
            MediaFormat='m4a',
            LanguageCode='ja-JP'
        )
        print(f"[DEBUG 2] ジョブ登録成功！ステータス: {response['TranscriptionJob']['TranscriptionJobStatus']}")
        
        # 完了待ちループ
        loop_count = 0
        while True:
            status = transcribe.get_transcription_job(TranscriptionJobName=job_name)
            job_status = status['TranscriptionJob']['TranscriptionJobStatus']
            
            loop_count += 1
            print(f"[DEBUG 3-{loop_count}] 確認中... 現在のステータス: {job_status}")
            
            if job_status in ['COMPLETED', 'FAILED']:
                break
            time.sleep(2) # 2秒待機
            
        print(f"[DEBUG 4] ループ終了。最終ステータス: {job_status}")
            
        if job_status == 'COMPLETED':
            transcript_uri = status['TranscriptionJob']['Transcript']['TranscriptFileUri']
            print(f"[DEBUG 5] 結果URL取得: {transcript_uri}")
            
            with urllib.request.urlopen(transcript_uri) as res:
                data = json.loads(res.read().decode())
                text = data['results']['transcripts'][0]['transcript']
                print(f"[DEBUG 6] 抽出成功！テキスト: {text}")
                return text
        else:
            # FAILEDの場合、失敗理由を取得
            failure_reason = status['TranscriptionJob'].get('FailureReason', '理由不明')
            print(f"[DEBUG 🚨 FAILED] 失敗理由: {failure_reason}")
            return "（文字起こし失敗だガオ）"

    except Exception as e:
        print(f"[DEBUG 🚨 EXCEPTION] プログラムエラー発生: {str(e)}")
        return "（文字起こし失敗だガオ）"

# --- 🦁 2. AIアドバイス生成関数 ---
def generate_lion_advice(transcript, power_db):
    prompt = f"""
あなたはサバンナの王、熱血系のライオンです。
後輩ライオン（ユーザー）が吠えました。以下の情報をもとに、アドバイスと評価を1〜2文で熱く返信してください。

【情報】
- 吠えた言葉: 「{transcript}」
- 声のデシベル(0に近いほど大きい): {power_db} dB

【ルール】
- 語尾は「ガオ！」や「だぜ！」など熱血に。
- デシベルが-10以上なら「すげぇ声だ！」、-30以下なら「腹から声出せ！」など、数値に触れること。
"""
    
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 200,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.7
    })

    try:
        response = bedrock.invoke_model(
            body=body, 
            modelId='anthropic.claude-3-haiku-20240307-v1:0', # 高速で安価なHaikuモデルを使用
            accept='application/json', 
            contentType='application/json'
        )
        response_body = json.loads(response.get('body').read())
        return response_body.get('content')[0].get('text')
    except Exception as e:
        print(f"Bedrock Error: {e}")
        return "通信エラーでアドバイスできないガオ！"

# --- メインハンドラ ---
def lambda_handler(event, context):
    try:
        http_method = event.get('httpMethod')
        resource = event.get('resource')
        query_params = event.get('queryStringParameters') or {}
        # ----------------------------------------
        # 🚀 投稿する (POST /roars)
        # ----------------------------------------
        if resource == '/roars' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'), parse_float=decimal.Decimal)
            s3_key = body.get('s3Key', '')
            roar_power = body.get('roarPower', decimal.Decimal('0'))
            
            # 1. 🌟 文字起こしを実行（数秒待つ）
            transcript = transcribe_audio(s3_key)
            
            # 2. 🌟 AIにアドバイスをもらう
            ai_advice = generate_lion_advice(transcript, float(roar_power))
            
            post_id = str(uuid.uuid4())
            item = {
                'postId': post_id,
                'userId': body.get('userId', 'guest'),
                'userName': body.get('userName', '名無しライオン'),
                's3Key': s3_key,
                'roarPower': roar_power,
                # 3. 🌟 新しい項目をデータベースに保存
                'transcript': transcript, 
                'aiAdvice': ai_advice,    
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
            table.put_item(Item=item)
            
            # 返信にもAIの結果を含める
            return {
                'statusCode': 200, 
                'headers': CORS_HEADERS, 
                'body': json.dumps({
                    'message': '保存大成功！', 
                    'postId': post_id,
                    'transcript': transcript,
                    'aiAdvice': ai_advice
                })
            }

        # ----------------------------------------
        # 2. タイムライン取得 (GET /timeline)
        # ----------------------------------------
        elif resource == '/timeline' and http_method == 'GET':
            user_id = query_params.get('userId')
            
            if user_id:
                response = table.scan(FilterExpression=Attr('userId').eq(user_id))
            else:
                response = table.scan()
            posts = response.get('Items', [])

            # 🌟 ここで「最新のユーザー情報」をすべて取得
            user_response = user_table.scan()
            users = {u['userId']: u for u in user_response.get('Items', [])}

            # 🌟 投稿データの名前を、最新のユーザー情報の名前で上書きする！
            for post in posts:
                uid = post.get('userId')
                if uid in users:
                    # 最新の名前があれば上書き。なければ投稿時の名前を使う
                    post['userName'] = users[uid].get('userName', post.get('userName', '名無し'))
                    # ついでにアバターのキーも渡せるようにしておくと便利
                    post['avatarS3Key'] = users[uid].get('avatarS3Key', '')
                
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(posts, cls=DecimalEncoder)}

        # ----------------------------------------
        # 3. プロフィール更新 (POST /profile)
        # ----------------------------------------
        elif resource == '/profile' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            user_id = body.get('userId')
            
            user_item = {
                'userId': user_id,
                'userName': body.get('userName', ''),
                'avatarS3Key': body.get('avatarS3Key', ''),
                'updatedAt': datetime.utcnow().isoformat() + 'Z'
            }
            user_table.put_item(Item=user_item)
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'プロフ更新成功！'})}

        # ----------------------------------------
        # 4. プロフィール取得 (GET /profile)
        # ----------------------------------------
        elif resource == '/profile' and http_method == 'GET':
            user_id = query_params.get('userId')
            response = user_table.get_item(Key={'userId': user_id})
            item = response.get('Item', {})
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(item)}
        # ----------------------------------------
        # 5. リアクション追加 (POST /reactions)
        # ----------------------------------------
        elif resource == '/reactions' and http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            post_id = body.get('postId')
            user_id = body.get('userId')
            reaction_type = body.get('reactionType')
            
            # 🌟 変更点：最後に #{reaction_type} を追加して、種類ごとに別の保存データにする！
            reaction_id = f"{post_id}#{user_id}#{reaction_type}"
            
            reaction_table.put_item(Item={
                'reactionId': reaction_id,
                'postId': post_id,
                'userId': user_id,
                'reactionType': reaction_type,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            })
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'リアクション追加！'})}

        # ----------------------------------------
        # 6. リアクション削除 (DELETE /reactions)
        # ----------------------------------------
        elif resource == '/reactions' and http_method == 'DELETE':
            post_id = query_params.get('postId')
            user_id = query_params.get('userId')
            reaction_type = query_params.get('reactionType') # 🌟 これを追加！
            
            # 🌟 変更点：消す時も「どの種類のリアクションを消すか」を指定する！
            reaction_id = f"{post_id}#{user_id}#{reaction_type}"
            reaction_table.delete_item(Key={'reactionId': reaction_id})
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'リアクション削除！'})}

        # ----------------------------------------
        # 7. 投稿のリアクション一覧取得 (GET /reactions)
        # ----------------------------------------
        elif resource == '/reactions' and http_method == 'GET':
            post_id = query_params.get('postId')
            
            response = reaction_table.scan(FilterExpression=Attr('postId').eq(post_id))
            reactions = response.get('Items', [])
            
            grouped = {}
            for r in reactions:
                rt = r.get('reactionType')
                if rt not in grouped:
                    grouped[rt] = {'count': 0, 'users': []}
                grouped[rt]['count'] += 1
                grouped[rt]['users'].append(r.get('userId'))
            
            return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': json.dumps(grouped)}

        return {'statusCode': 400, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'Unsupported method'})}

    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500, 'headers': CORS_HEADERS, 'body': json.dumps({'message': 'Internal error', 'errorDetail': str(e)})}