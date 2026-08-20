"""
Amazon MQ (RabbitMQ) consumer.
  pip3 install pika
  export MQ_URL='amqps://admin:SkillsRabbit2026!@b-xxxx.mq.ap-northeast-2.on.aws:5671'
  python3 consumer.py
"""
import os
import pika

params = pika.URLParameters(os.environ["MQ_URL"])
conn = pika.BlockingConnection(params)
ch = conn.channel()
ch.queue_declare(queue="orders", durable=True)

n = 0
for method, props, body in ch.consume("orders", inactivity_timeout=10):
    if body is None:
        break
    n += 1
    print(f"got {body.decode()}")
    ch.basic_ack(method.delivery_tag)
print(f"consumed {n}")
conn.close()
