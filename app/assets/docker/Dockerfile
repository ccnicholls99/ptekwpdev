FROM alpine:latest
USER root

RUN deluser assetuser || true \
    && adduser -D assetuser

WORKDIR /usr/src/ptekwpdev
RUN mkdir -p /usr/src/ptekwpdev/assets/{plugins,themes,static} \
    && chown -R assetuser:assetuser /usr/src/ptekwpdev/assets

USER assetuser
