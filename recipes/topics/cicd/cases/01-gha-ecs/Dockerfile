FROM public.ecr.aws/docker/library/python:3.12-slim
WORKDIR /app
COPY app.py .
ENV APP_VERSION=v1
EXPOSE 8080
CMD ["python","app.py"]
