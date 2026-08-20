"""
Amazon MQ (RabbitMQ) producer. amqps(TLS) 5671 로 발행.
  pip3 install pika
  export MQ_URL='amqps://admin:SkillsRabbit2026!@b-xxxx.mq.ap-northeast-2.on.aws:5671'
  python3 producer.py
"""
import os
import pika

params = pika.URLParameters(os.environ["MQ_URL"])   # amqps:// 면 TLS 자동
conn = pika.BlockingConnection(params)
ch = conn.channel()
ch.queue_declare(queue="orders", durable=True)
for i in range(10):
    ch.basic_publish(
        exchange="", routing_key="orders",
        body=f'{{"order_id": {i}}}',
        properties=pika.BasicProperties(delivery_mode=2),  # persistent
    )
    print(f"sent order_id={i}")
conn.close()
print("done")
