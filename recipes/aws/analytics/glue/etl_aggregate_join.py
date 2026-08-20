"""
Glue ETL: 집계 + 조인 + Data Quality. 여러 소스를 결합해 요약 테이블 생성.
Spark SQL 로 변환 — DynamicFrame 을 DataFrame 으로 바꿔 SQL 사용.

--JOB_NAME, --EVENTS (s3 이벤트), --USERS (s3 유저), --DST (출력)
"""
import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ["JOB_NAME", "EVENTS", "USERS", "DST"])
sc = SparkContext()
glue = GlueContext(sc)
spark = glue.spark_session
job = Job(glue)
job.init(args["JOB_NAME"], args)

# 소스 로드
events = glue.create_dynamic_frame.from_options(
    "s3", {"paths": [args["EVENTS"]], "recurse": True}, format="json"
).toDF()
users = glue.create_dynamic_frame.from_options(
    "s3", {"paths": [args["USERS"]], "recurse": True}, format="json"
).toDF()

events.createOrReplaceTempView("events")
users.createOrReplaceTempView("users")

# 집계 + 조인을 Spark SQL 로
result = spark.sql("""
    SELECT
        u.grade,
        e.event_type,
        COUNT(*)        AS cnt,
        SUM(e.value)    AS total,
        AVG(e.value)    AS avg_value
    FROM events e
    JOIN users u ON e.user_id = u.user_id
    GROUP BY u.grade, e.event_type
""")

# Data Quality: 음수 value 는 제외 (간단 규칙)
result = result.filter("total >= 0")

# Parquet 저장
out = DynamicFrame.fromDF(result, glue, "out")
glue.write_dynamic_frame.from_options(
    out, "s3", {"path": args["DST"]}, format="parquet"
)

job.commit()
