FROM dart:3.10.8

WORKDIR /app

COPY . /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    if ! ldconfig -p | grep -q "libsqlite3.so"; then \
      so0="$(ldconfig -p | awk '/libsqlite3\.so\.0/{print $NF; exit}')"; \
      if [ -n "$so0" ]; then ln -sf "$so0" "$(dirname "$so0")/libsqlite3.so"; fi; \
    fi

RUN chmod +x /app/backend/entrypoint.sh

WORKDIR /app/backend

RUN dart pub get
RUN mkdir -p /app/backend/build
RUN dart build cli --target bin/server.dart --output /app/backend/build
RUN chmod +x /app/backend/build/bundle/bin/server

ENV PORT=8080

EXPOSE 8080

CMD ["bash", "/app/backend/entrypoint.sh"]
