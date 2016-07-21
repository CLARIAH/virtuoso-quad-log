FROM python:2


RUN pip install resync
COPY oai-rs/resource_list.py /
COPY entrypoint.sh /entrypoint.sh

CMD ["/entrypoint.sh"]