FROM python:3.13-alpine

WORKDIR /app
COPY proof/mock_upstream.py /app/mock_upstream.py

ENTRYPOINT ["python", "/app/mock_upstream.py", "--host", "0.0.0.0", "--port", "18081"]
