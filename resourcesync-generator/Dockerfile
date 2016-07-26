FROM python:2


RUN pip install resync
COPY oai-rs/rsync.py /
COPY oai-rs/synchronizer.py /
COPY entrypoint.sh /entrypoint.sh

CMD ["/entrypoint.sh"]