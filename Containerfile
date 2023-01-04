# Dockerfile to test brightness-zig in the context of writing to /var folder

FROM zig

RUN apk add mpdecimal-dev

RUN mkdir /opt/brightness-zig
WORKDIR /opt/brightness-zig
COPY ./ ./

RUN ls -l --color

# ENTRYPOINT zig test src/brightnessctl-wrapper.zig

