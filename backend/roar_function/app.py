import json
import boto3
import os
import uuid
from datetime import datetime
import decimal

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, decimal.Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

TABLE_NAME = os.environ.get('TABLE_NAME')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

# 🌟 追加：絶対に返す「最強のCORS許可証」
CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
}

def lambda_handler(event, context):
    try:
        http_method = event.get('httpMethod')

        if http_method == 'POST':
            body = json.loads(event.get('body', '{}'), parse_float=decimal.Decimal)

            user_id = body.get('userId', 'guest')
            user_name = body.get('userName', '名無しライオン')
            s3_key = body.get('s3Key', '')
            roar_power = body.get('roarPower', decimal.Decimal('0'))
            message = body.get('message', '')

            post_id = str(uuid.uuid4())
            timestamp = datetime.utcnow().isoformat() + 'Z'

            item = {
                'postId': post_id,
                'userId': user_id,
                'userName': user_name,
                's3Key': s3_key,
                'roarPower': roar_power,
                'message': message,
                'timestamp': timestamp
            }
            table.put_item(Item=item)

            return {
                'statusCode': 200,
                'headers': CORS_HEADERS, # 👈 許可証をセット
                'body': json.dumps({'message': 'ガオォォ！保存大成功！', 'postId': post_id})
            }

        elif http_method == 'GET':
            response = table.scan()
            items = response.get('Items', [])
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS, # 👈 許可証をセット
                'body': json.dumps(items, cls=DecimalEncoder)
            }

        return {
            'statusCode': 400, 
            'headers': CORS_HEADERS, # 👈 許可証をセット
            'body': json.dumps({'message': 'Unsupported method'})
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        # 🚨 超重要：エラーの時も「絶対に」許可証を返す！！
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS, # 👈 これがないとブラウザがFetchエラーを起こす
            'body': json.dumps({'message': 'Internal server error', 'errorDetail': str(e)})
        }