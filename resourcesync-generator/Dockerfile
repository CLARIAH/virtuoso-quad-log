FROM python:2


RUN pip install resync
COPY oai-rs/resource-list.py /
COPY entrypoint.sh /entrypoint.sh

CMD ["/entrypoint.sh"]