FROM ghcr.io/tigerbeetle/tigerbeetle:0.17.5 AS upstream

FROM debian:bookworm-slim
COPY --from=upstream /tigerbeetle /usr/local/bin/tigerbeetle
COPY docker/tigerbeetle/entrypoint.sh /usr/local/bin/hydra-tigerbeetle
RUN chmod 0755 /usr/local/bin/hydra-tigerbeetle
ENTRYPOINT ["/usr/local/bin/hydra-tigerbeetle"]
