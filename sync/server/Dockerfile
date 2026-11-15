# Build from sync/: docker build -t cu-sync-server -f server/Dockerfile .
FROM oven/bun:1-alpine AS web
WORKDIR /src/web
COPY web/package.json web/bun.lock ./
RUN bun install --frozen-lockfile
COPY web ./
RUN bun run build

# Static musl build with the web app embedded; the final image is just the binary.
FROM rust:1-alpine AS build
RUN apk add --no-cache musl-dev gcc
WORKDIR /src/server
COPY server/Cargo.toml server/Cargo.lock ./
COPY server/src ./src
COPY --from=web /src/web/dist /src/web/dist
RUN cargo build --release --locked && mkdir /data

FROM scratch
COPY --from=build /src/server/target/release/cu-sync-server /cu-sync-server
COPY --from=build --chown=65534:65534 /data /data
USER 65534:65534
ENV CU_SYNC_DB=/data/sync.db CU_SYNC_BIND=0.0.0.0:8787
EXPOSE 8787
VOLUME /data
ENTRYPOINT ["/cu-sync-server"]
