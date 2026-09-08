FROM python:3.11-slim
RUN pip install --no-cache-dir python-snappy cramjam -q 2>&1 | tail -n 1
WORKDIR /app
COPY receiver.py /app/receiver.py
EXPOSE 8080
CMD ["python", "-u", "/app/receiver.py", "8080"]
