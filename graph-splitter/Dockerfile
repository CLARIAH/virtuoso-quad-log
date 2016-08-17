FROM ubuntu

RUN apt-get update && apt-get install -y \
coreutils

COPY entrypoint.sh /
COPY split-graphs.sh /

RUN chmod +x ./entrypoint.sh
RUN chmod +x ./split-graphs.sh

ENTRYPOINT ["/entrypoint.sh"]