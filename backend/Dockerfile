FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY assistant.py .
# ANTHROPIC_API_KEY and LIVO_DEVICE_TOKENS come from the environment (never baked into the image).
EXPOSE 8000
CMD ["uvicorn", "assistant:app", "--host", "0.0.0.0", "--port", "8000"]
