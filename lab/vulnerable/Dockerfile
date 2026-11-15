# The vulnerable container image.
#
# This is what a participant gets dropped INTO for every level. It is a normal,
# unremarkable Alpine container with a handful of common tools preinstalled.
# The image itself is not the vulnerability.
# Therun flags the host applies when starting
# it are (see lab/host/scripts/levels.conf). That is the whole lesson: the same
# image is secure or trivially escapable depending only on how it is run.

# Build stage: compile the open_by_handle_at helper used by Level 7 
# Built here (not shipped as a committed binary) so it is correct for whatever
# CPU architecture the participant builds on -- amd64 laptops and Apple Silicon
# (arm64) alike.
FROM alpine:3.20 AS build
RUN apk add --no-cache build-base
COPY handle_reader.c /tmp/handle_reader.c
RUN gcc -static -O2 -o /handle-read /tmp/handle_reader.c

# The actual container image
FROM alpine:3.20

RUN apk add --no-cache \
      bash \
      docker-cli \
      util-linux \
      curl \
      jq \
      procps

RUN adduser -D -u 1000 player

# A tiny, generic open_by_handle_at demo tool (see handle_reader.c).
COPY --from=build /handle-read /usr/local/bin/handle-read

WORKDIR /root
CMD ["/bin/bash"]
