FROM ghcr.io/cirruslabs/flutter:3.38.9

WORKDIR /app

COPY . /app

RUN flutter pub get

ENV PORT=8080

EXPOSE 8080

CMD ["dart", "run", "bin/hailo_backend.dart"]
