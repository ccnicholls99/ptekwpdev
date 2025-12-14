FROM alpine:latest
USER root

RUN deluser assetuser || true \
    && adduser -D assetuser

WORKDIR /usr/src/ptekwpdev
RUN mkdir -p /usr/src/ptekwpdev/assets/plugins \
    && mkdir -p /usr/src/ptekwpdev/assets/themes \
    && mkdir -p /usr/src/ptekwpdev/assets/static \  
    && chown -R assetuser:assetuser /usr/src/ptekwpdev/assets

USER assetuser
