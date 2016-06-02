# build quad logger essentials
# Usage:
# $ docker build -t {repository}/virtuoso-quad-log:{version} -f Dockerfile.ql .

FROM python:2

ENV VIRTUOSO_VERSION 7.2.0

RUN pip install resync

#############################################################################
# Start copy from https://github.com/EolDocker/virtuoso/blob/master/Dockerfile
# The MIT License (MIT)
#
# Copyright (c) 2014 EolDocker
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
RUN apt-get update && apt-get -y install \
  dpkg-dev build-essential autoconf \
  automake libtool flex bison gperf \
  gawk m4 make odbcinst libxml2-dev \
  libssl-dev libreadline-dev openssl net-tools wget && \
  \
  wget --no-check-certificate \
  https://github.com/openlink/virtuoso-opensource/archive/v$VIRTUOSO_VERSION.tar.gz && \
  \
  tar zxvf v$VIRTUOSO_VERSION.tar.gz && \
  cd /virtuoso-opensource-$VIRTUOSO_VERSION && \
  \
  ./autogen.sh && \
  ./configure CFLAGS="-O2" --prefix=/usr/local --with-readline && \
  \
  make && \
  \
  make install && \
  \
  rm /v$VIRTUOSO_VERSION.tar.gz && \
  \
  rm -rf /virtuoso-opensource-$VIRTUOSO_VERSION && \
  \
  apt-get -y purge \
  dpkg-dev build-essential autoconf \
  automake libtool flex bison gperf \
  gawk m4 make libxml2-dev \
  libssl-dev libreadline-dev net-tools wget && \
  \
  apt-get clean autoclean && \
  \
  apt-get autoremove -y &&\
  \
  rm -rf /var/lib/{apt,dpkg,cache,log}/ &&\
  \
  mkdir /var/log/virtuoso-http


EXPOSE 8890 1111
# End copy from https://github.com/EolDocker/virtuoso/blob/master/Dockerfile
#############################################################################

COPY virtuoso.ini /usr/local/var/lib/virtuoso/db/virtuoso.ini
COPY oai-rs/resource-list.py /resource-list.py
COPY entrypoint.sh /entrypoint.sh
COPY parse_trx.sql /parse_trx.sql
COPY generate-rdfpatch.sh /generate-rdfpatch.sh

ENTRYPOINT ["/entrypoint.sh"]

