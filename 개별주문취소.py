import base64
import hashlib
import hmac
import json
import uuid
import httplib2

ACCESS_TOKEN = '{access token}'
SECRET_KEY = bytes('{secret key}', 'utf-8')


def get_encoded_payload(payload):
    payload['nonce'] = str(uuid.uuid4())

    dumped_json = json.dumps(payload)
    encoded_json = base64.b64encode(bytes(dumped_json, 'utf-8'))
    return encoded_json


def get_signature(encoded_payload):
    signature = hmac.new(SECRET_KEY, encoded_payload, hashlib.sha512)
    return signature.hexdigest()


def get_response(action, payload):
    url = '{}{}'.format('https://api.coinone.co.kr', action)

    encoded_payload = get_encoded_payload(payload)

    headers = {
        'Content-type': 'application/json',
        'X-COINONE-PAYLOAD': encoded_payload,
        'X-COINONE-SIGNATURE': get_signature(encoded_payload),
    }

    http = httplib2.Http()
    response, content = http.request(url, 'POST', headers=headers)

    return content


print(get_response(action='/v2.1/order/cancel', payload={
    'access_token': ACCESS_TOKEN,
    'user_order_id': 'd85cc6af-b131-4398-b269-ddbafa760a39',
    'quote_currency': 'KRW',
    'target_currency': 'BTC',
}))
