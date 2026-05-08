FROM python:3.12-slim

WORKDIR /opt/ml/code

COPY serve.py .

ENV PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/ping')" || exit 1

ENTRYPOINT ["python3", "serve.py"]
