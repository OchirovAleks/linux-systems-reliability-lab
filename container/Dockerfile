FROM python:3.14-slim

RUN groupadd --gid 10001 reliability-web \
    && useradd --uid 10001 --gid reliability-web --no-create-home \
        --home-dir /nonexistent --shell /usr/sbin/nologin reliability-web

WORKDIR /app
COPY --chown=root:reliability-web index.html /app/index.html
RUN chmod 0440 /app/index.html

USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["python3", "-u", "-m", "http.server", "8080", "--bind", "0.0.0.0"]
