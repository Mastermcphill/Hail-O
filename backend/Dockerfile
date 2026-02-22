FROM dart:3.10.8

WORKDIR /app

COPY . /app

RUN chmod +x /app/backend/entrypoint.sh

WORKDIR /app/backend

RUN dart pub get

ENV PORT=8080

EXPOSE 8080

CMD ["bash", "/app/backend/entrypoint.sh"]
