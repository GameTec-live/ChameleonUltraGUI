# Static musl build; the final image is just the binary.
FROM rust:1-alpine AS build
RUN apk add --no-cache musl-dev gcc
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked && mkdir /data

FROM scratch
COPY --from=build /src/target/release/cu-sync-server /cu-sync-server
COPY --from=build --chown=65534:65534 /data /data
USER 65534:65534
ENV CU_SYNC_DB=/data/sync.db CU_SYNC_BIND=0.0.0.0:8787
EXPOSE 8787
VOLUME /data
ENTRYPOINT ["/cu-sync-server"]
