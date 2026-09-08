FROM python:3.12-slim
WORKDIR /app
COPY app.py .
RUN pip install --no-cache-dir prometheus_client -q
EXPOSE 8000
CMD ["python", "-u", "app.py"]
