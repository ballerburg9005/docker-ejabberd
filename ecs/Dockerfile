ARG MIX_IMAGE=docker.io/ballerburg9005/docker-ejabberd-mix-official-arm:latest
FROM docker.io/golang:1.27-alpine AS api
RUN go install -v \
    github.com/processone/ejabberd-api/cmd/ejabberd@latest \
    && mv bin/ejabberd bin/ejabberdapi

FROM ${MIX_IMAGE} AS builder
ARG VERSION
ENV VERSION=${VERSION:-latest} \
    MIX_ENV=prod
LABEL maintainer="ProcessOne <contact@process-one.net>" \
    product="Ejabberd Community Server builder"

# Get ejabberd sources, dependencies, configuration
RUN git clone https://github.com/processone/ejabberd.git
WORKDIR /ejabberd
COPY vars.config .
COPY config.exs config/
COPY rel/*exs rel/
RUN git checkout ${VERSION/latest/HEAD} \
    \
    && if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then \
        echo '{vsn, "'"$VERSION.0"'"}.' >> vars.config; \
    else \
        echo '{vsn, "0.0.0"}.' >> vars.config; \
    fi \
    \
    && mix deps.get \
    && (cd deps/eimp; ./configure)

# Compile
RUN MIX_ENV=prod mix release

# Prepare runtime environment
RUN mkdir runtime \
    && tar -C runtime -zxf _build/prod/ejabberd-*.tar.gz \
    && cd runtime \
    && cp releases/*/start.boot bin \
    && cp releases/*/start_clean.boot bin \
    && echo 'beam_lib:strip_files(filelib:wildcard("lib/*/ebin/*beam")), init:stop().' | erl >/dev/null \
    && mv erts*/bin/* bin \
    && EJABBERD_VERSION=`(cd releases; ls -1 -d *.*.*)` \
    && rm -rf releases erts* bin/*src bin/dialyzer bin/typer etc \
    && rm bin/ejabberd \
    && mkdir lib/ejabberd-$EJABBERD_VERSION/priv/bin \
    && cp /usr/lib/elixir/bin/* bin/ \
    && sed -i 's|ERL_EXEC="erl"|ERL_EXEC="/home/ejabberd/bin/erl"|' bin/elixir \
    && cp /ejabberd/tools/captcha*sh bin/ \
    && cp -r /ejabberd/sql lib/ejabberd-*/priv

# Runtime container
FROM docker.io/alpine:3.24
ARG VERSION
ARG VCS_REF
ARG BUILD_DATE
ENV TERM=xterm \
    LC_ALL=C.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    REPLACE_OS_VARS=true \
    HOME=/home/ejabberd \
    PATH="$PATH:/home/ejabberd/bin" \
    VERSION=${VERSION:-latest}
LABEL maintainer="ProcessOne <contact@process-one.net>" \
    product="Ejabberd Community Server Official Docker Image" \
    version=$VERSION \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.vcs-url="https://github.com/processone/docker-ejabberd" \
    org.label-schema.build-date=$BUILD_DATE \
    org.label-schema.name="Ejabberd Community Server Official Docker Image" \
    org.label-schema.description="Robust, Scalable and Extensible Realtime Server using XMPP, MQTT and SIP" \
    org.label-schema.url="https://www.ejabberd.im/" \
    org.label-schema.vendor="ProcessOne" \
    org.label-schema.version=$VERSION \
    org.label-schema.schema-version="1.0"

# Create directory structure and user for ejabberd
RUN addgroup ejabberd -g 9000 \
    && adduser -s /bin/sh -D -G ejabberd ejabberd -u 9000 \
    && mkdir -p /home/ejabberd/conf /home/ejabberd/database /home/ejabberd/logs /home/ejabberd/upload \
    && chown -R ejabberd:ejabberd /home/ejabberd \
    && ln -fs /home/ejabberd /opt/ejabberd \
    && ln -fs /home/ejabberd /opt/ejabberd-$VERSION

# Install required dependencies
RUN apk upgrade --update-cache --no-progress \
    && apk add \
    expat \
    freetds \
    gd \
    jpeg \
    libgd \
    libpng \
    libstdc++ \
    libwebp \
    ncurses-libs \
    openssl \
    sqlite \
    sqlite-libs \
    tini \
    git \
    imagemagick \
    ghostscript-fonts \
    bash \
    unixodbc \
    yaml \
    zlib \
    && ln -fs /usr/lib/libtdsodbc.so.0 /usr/lib/libtdsodbc.so \
    && rm -rf /var/cache/apk/*

# Install ejabberd
WORKDIR $HOME
COPY --from=builder /ejabberd/runtime .
COPY bin/* bin/
COPY --from=api /go/bin/ejabberdapi bin/ejabberdapi
RUN chmod 755 bin/ejabberdctl bin/ejabberdapi bin/erl bin/captcha*.sh \
    && mkdir -p /home/ejabberd/sql \
    && cp /home/ejabberd/lib/ejabberd-*/priv/sql/* /home/ejabberd/database/ \
    && cp /home/ejabberd/lib/ejabberd-*/priv/sql/* /home/ejabberd/sql/
COPY --chown=ejabberd:ejabberd conf conf/
ADD --chown=ejabberd:ejabberd https://download.process-one.net/cacert.pem conf/cacert.pem

# Keep the legacy private-bin CAPTCHA paths in addition to upstream's
# $HOME/bin/ paths, so existing captcha_cmd settings continue to work.
RUN for dir in lib/ejabberd-*/priv/bin; do \
        cp bin/captcha*.sh "$dir/"; \
    done

# Install the two registration modules into the image, not on first boot.
# BuildKit RUN steps get their own network namespace; the 2021 randomized
# host-port wait and netcat debug hooks are no longer used.
USER ejabberd
RUN set -eu; \
    bin/ejabberdctl start; \
    ready=0; \
    for i in $(seq 1 90); do \
        if bin/ejabberdctl started >/dev/null 2>&1; then ready=1; break; fi; \
        sleep 2; \
    done; \
    if [ "$ready" != 1 ]; then \
        tail -100 logs/ejabberd.log || true; \
        exit 1; \
    fi; \
    bin/ejabberdctl modules_update_specs; \
    bin/ejabberdctl module_install mod_default_rooms; \
    bin/ejabberdctl module_install mod_default_contacts; \
    bin/ejabberdctl stop; \
    (killall epmd || true)

# Setup runtime environment
USER ejabberd
VOLUME ["$HOME/database","$HOME/conf","$HOME/logs","$HOME/upload"]
EXPOSE 1880 1883 4369-4399 5210 5222 5269 5280 5443 5478 7777 50000-50099

ENTRYPOINT ["/sbin/tini","--","/home/ejabberd/bin/ejabberdctl"]
CMD ["foreground"]
