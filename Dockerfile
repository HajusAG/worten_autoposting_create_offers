FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TZ=Europe/Kiev \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata ca-certificates \
 && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY script.py ./

# Container stays alive; cron schedule is configured in Coolify Scheduled Tasks
# (command: python /app/script.py, frequency: 15 6 * * *, TZ: Europe/Kiev).
CMD ["tail", "-f", "/dev/null"]
