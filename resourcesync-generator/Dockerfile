FROM python:2


RUN pip install resync
COPY oai-rs/rsync.py /
COPY oai-rs/syncdirector.py /
COPY oai-rs/zipsynchronizer.py /
COPY entrypoint.sh /entrypoint.sh

CMD ["/entrypoint.sh"]