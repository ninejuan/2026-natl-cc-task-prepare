"""
Glue ETL: S3 JSON -> 변환/집계 -> S3 Parquet. Glue job(Spark) 스크립트.
--JOB_NAME, --SRC (s3 json 경로), --DST (s3 parquet 출력) 인자를 받는다.

Glue 4.0/5.0 (Spark). DynamicFrame 으로 스키마 유연 처리 + Parquet 저장.
"""
import sys
from awsglue.transforms import ApplyMapping
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ["JOB_NAME", "SRC", "DST"])
sc = SparkContext()
glue = GlueContext(sc)
spark = glue.spark_session
job = Job(glue)
job.init(args["JOB_NAME"], args)

# 1) S3 JSON 읽기 (DynamicFrame: 스키마 자동 추론)
src = glue.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"paths": [args["SRC"]], "recurse": True},
    format="json",
)

# 2) 타입 정리 (문자열 id -> int 등)
mapped = ApplyMapping.apply(
    frame=src,
    mappings=[
        ("event_type", "string", "event_type", "string"),
        ("id", "int", "id", "int"),
        ("dt", "string", "dt", "string"),
    ],
)

# 3) Parquet 로 저장 (dt 파티션)
glue.write_dynamic_frame.from_options(
    frame=mapped,
    connection_type="s3",
    connection_options={"path": args["DST"], "partitionKeys": ["dt"]},
    format="parquet",
)

job.commit()
