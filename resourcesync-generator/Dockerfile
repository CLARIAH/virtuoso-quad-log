FROM python:2

RUN pip install resync
COPY oai-rs/*.py /
COPY entrypoint.sh /

CMD ["/entrypoint.sh"]