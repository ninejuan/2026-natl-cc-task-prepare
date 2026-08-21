"""EC2 stopped → 자동 재시작 (EventBridge EC2 state-change → Lambda). 실검증됨(Invocations=1→running).
role: ec2:StartInstances, ec2:DescribeInstances. rule event-pattern:
  {"source":["aws.ec2"],"detail-type":["EC2 Instance State-change Notification"],"detail":{"state":["stopped"]}}
"""
import boto3
def handler(event, context):
    iid = event["detail"]["instance-id"]
    if event["detail"]["state"] == "stopped":
        boto3.client("ec2").start_instances(InstanceIds=[iid])
        return {"restarted": iid}
    return {"ignored": iid}
