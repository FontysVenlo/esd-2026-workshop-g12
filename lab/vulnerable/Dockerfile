# The vulnerable container image.
#
# This is what a participant gets dropped INTO for every level. It is a normal,
# unremarkable Alpine container with a handful of common tools preinstalled.
# The image itself is not the vulnerability -- the
# run flags the host applies when starting
# it are (see lab/host/scripts/levels.conf). That is the whole lesson: the same
# image is secure or trivially escapable depending only on how it is run.
FROM alpine:3.20

RUN apk add --no-cache \
      bash \
      docker-cli \
      util-linux \
      curl \
      jq \
      procps

RUN adduser -D -u 1000 player

WORKDIR /root
CMD ["/bin/bash"]
