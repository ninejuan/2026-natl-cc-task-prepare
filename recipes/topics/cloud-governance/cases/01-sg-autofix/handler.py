"""SG 0.0.0.0/0 인바운드 자동 복구 Lambda (Cloud governance 3년 연속 출제).
트리거: EventBridge rule — CloudTrail AuthorizeSecurityGroupIngress.
동작: 이벤트에서 groupId + 추가된 규칙 추출 → 0.0.0.0/0 규칙 revoke → SNS 알림.
채점: SG 에 22/0.0.0.0/0 추가 → 180초 내 인바운드 0.
role 권한: ec2:RevokeSecurityGroupIngress, ec2:DescribeSecurityGroups, sns:Publish.
"""
import os
import boto3

ec2 = boto3.client("ec2")


def handler(event, context):
    detail = event.get("detail", {})
    params = detail.get("requestParameters", {})
    gid = params.get("groupId")
    if not gid:
        return {"skipped": "no groupId"}

    to_revoke = []
    for item in params.get("ipPermissions", {}).get("items", []):
        open_ranges = [r for r in item.get("ipRanges", {}).get("items", [])
                       if r.get("cidrIp") == "0.0.0.0/0"]
        if open_ranges:
            to_revoke.append({
                "IpProtocol": item["ipProtocol"],
                "FromPort": item.get("fromPort", 0),
                "ToPort": item.get("toPort", 65535),
                "IpRanges": [{"CidrIp": "0.0.0.0/0"}],
            })

    if to_revoke:
        ec2.revoke_security_group_ingress(GroupId=gid, IpPermissions=to_revoke)
        msg = f"reverted {len(to_revoke)} open (0.0.0.0/0) rule(s) on {gid}"
        topic = os.environ.get("TOPIC")
        if topic:
            boto3.client("sns").publish(TopicArn=topic, Subject="SG auto-remediation", Message=msg)
        return {"reverted": to_revoke, "group": gid}
    return {"nothing_to_revoke": gid}
