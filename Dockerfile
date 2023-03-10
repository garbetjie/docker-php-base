ARG PHP_VERSION

FROM alpine:3.16 AS fs

RUN mkdir /tmp/root
RUN wget https://github.com/just-containers/s6-overlay/releases/download/v3.1.2.1/s6-overlay-noarch.tar.xz -P /tmp
RUN wget https://github.com/just-containers/s6-overlay/releases/download/v3.1.2.1/s6-overlay-$(uname -m).tar.xz -P /tmp
RUN tar -C /tmp/root/ -Jxpf /tmp/s6-overlay-noarch.tar.xz
RUN tar -C /tmp/root/ -Jxpf /tmp/s6-overlay-$(uname -m).tar.xz
RUN mkdir /tmp/root/app

COPY bin/ /tmp/root/usr/local/bin/

# Copy core services.
COPY services/ /tmp/root/etc/s6-overlay/s6-rc.d


FROM php:${PHP_VERSION}-alpine3.16 AS shared

STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]

COPY --from=fs /tmp/root/ /
WORKDIR /app

ENV PUID=1000 \
    PGID=1000

RUN set -ex; \
    apk add --no-cache shadow su-exec; \
    rm -rf /var/www; \
    addgroup -g "$PGID" app; \
    adduser -s /bin/sh -G app -u "$PUID" -D app

# Define PHP INI configuration.
ENV PHP_EXPOSE_PHP="false" \
    PHP_DISPLAY_ERRORS="false" \
    PHP_DATE_TIMEZONE="" \
    PHP_ERROR_REPORTING="E_ALL & ~E_DEPRECATED & ~E_STRICT" \
    PHP_HTML_ERRORS="off" \
    PHP_MAX_EXECUTION_TIME=30 \
    PHP_MAX_INPUT_TIME=30 \
    PHP_MEMORY_LIMIT="64M" \
    PHP_POST_MAX_SIZE="8M" \
    PHP_SESSION_NAME="session" \
    PHP_SESSION_SAVE_HANDLER="files" \
    PHP_SESSION_SAVE_PATH="/tmp/sessions" \
    PHP_SYS_TEMP_DIR="/tmp" \
    PHP_UPLOAD_MAX_FILESIZE="8M"


FROM shared AS www

# Define FPM configuration.
ENV FPM_PM="static" \
    FPM_PM_MAX_CHILDREN="90%" \
    FPM_PM_MIN_SPARE_SERVERS=1 \
    FPM_PM_MAX_SPARE_SERVERS=3 \
    FPM_PM_MAX_REQUESTS=10000 \
    FPM_REQUEST_SLOWLOG_TIMEOUT=5 \
    FPM_SLOWLOG="/proc/self/fd/2" \
    FPM_REQUEST_TERMINATE_TIMEOUT=60

# Define nginx configuration.
ENV NGINX_ABSOLUTE_REDIRECT="on" \
    NGINX_FASTCGI_BUFFER_SIZE="16k" \
    NGINX_FASTCGI_BUFFERING="on" \
    NGINX_FASTCGI_BUFFERS="16 16k" \
    NGINX_FASTCGI_BUSY_BUFFERS_SIZE="32k" \
    NGINX_LOG_FORMAT="main" \
    NGINX_PORT=80 \
    NGINX_PORT_IN_REDIRECT="on" \
    NGINX_ROOT="/app"

COPY nginx.conf /etc/nginx/nginx.conf

RUN set -e; \
    apk add --no-cache nginx; \
    mkdir -p /etc/nginx/server.d; \
    rm -rf /var/www /etc/nginx/http.d/*.conf; \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/nginx \
          /etc/s6-overlay/s6-rc.d/user/contents.d/fpm; \
    mkdir -p /var/tmp/nginx /var/lib/nginx


FROM shared AS cli

CMD ["/command/with-contenv", "su-exec", "app:app", "php", "-a"]