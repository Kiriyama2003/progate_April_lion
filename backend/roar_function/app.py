import json
import boto3
import os
import uuid
from datetime import datetime
import decimal

# --- 1. DynamoDBから出す時の翻訳機 ---
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, decimal.Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

TABLE_NAME = os.environ.get('TABLE_NAME')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    try:
        http_method = event.get('httpMethod')

        if http_method == 'POST':
            # 👈 修正：送られてきたJSONの中の小数を、DynamoDBが好きな「Decimal」に自動変換して読み込む
            body = json.loads(event.get('body', '{}'), parse_float=decimal.Decimal)

            user_id = body.get('userId', 'guest')
            user_name = body.get('userName', '名無しライオン')
            s3_key = body.get('s3Key', '')
            # デフォルト値も Decimal にしておく
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
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
                },
                'body': json.dumps({'message': 'ガオォォ！保存大成功！', 'postId': post_id})
            }

        elif http_method == 'GET':
            response = table.scan()
            items = response.get('Items', [])
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
                },
                'body': json.dumps(items, cls=DecimalEncoder)
            }

        return {'statusCode': 400, 'body': 'Unsupported method'}

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'message': 'Internal server error', 'errorDetail': str(e)})
        }