FROM dart:3.10.8

WORKDIR /app

COPY . /app

WORKDIR /app/backend

RUN dart pub get

ENV PORT=8080

EXPOSE 8080

CMD ["dart", "run", "bin/server.dart"]
