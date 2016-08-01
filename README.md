# Virtuoso Quad Logger

This *virtuoso-quad-log* repository harbors tools for propagating and publishing changes in RDF-data
that are kept in a [Virtuoso triple store](http://virtuoso.openlinksw.com/). Two tools are 
essential in this process. These are:

1. **quad_logger** generates logs of all initial, added, mutated or deleted quads in a
[Virtuoso quad store](http://virtuoso.openlinksw.com/rdf-quad-store/) in the
[RDF-patch](https://afs.github.io/rdf-patch/) format.
2. **resourcesync-generator** enables the synchronisation of these logs over the internet by means
of the [Resource Sync Framework](http://www.openarchives.org/rs/1.0/resourcesync).

The **example-virtuoso-server** is for demonstration purposes. The tools can be deployed as
services under [Docker-compose](https://docs.docker.com/compose/).

## Overview

![Overview](/img/environment.png)

- The above image shows the quad_logger and the resourcesync_generator in their environment.
The Virtuoso server is instructed to log its transactions in log files. The quad_logger interacts
with the Virtuoso server by means of the Interactive SQL interface. It reads the 
transaction logs and transforms them to rdf-patch formatted files. The resourcesync-generator
bundles the rdf-patch files in zip-files and publishes them in accordance with the
Resource Sync Framework. Both quad_logger and resourcesync-generator can be deployed as
Docker containers. Here they are deployed as docker-compose services. Also 
the Http server (and the Virtuoso server) can be deployed as docker-compose service.

## Documentation
Documentation of the software in this repository is split over several files.
- **README.md** (this file) contains a general introduction.
- **[MOTIVATION.md](/MOTIVATION.md)** documents the background of this repository and 
motivates choices made.
- **[DEPLOY.md](/DEPLOY.md)** contains detailed instructions on the usage of the tools in this repository.
- **[VIRTUOSO_CONFIG.md](/VIRTUOSO_CONFIG.md)** communicates critical issues in your 
Virtuoso configuration.

## Quickstart

To launch a self-contained sandbox you can use the docker-compose-example-setup.yml

	docker-compose -f docker-compose-example-setup.yml build
	docker-compose -f docker-compose-example-setup.yml up

To connect the logger to a production virtuoso server, you can edit the environment variables in 
the docker-compose.yml and launch using that

	docker-compose build
	docker-compose up

This also launches a local nginx which you might, or might not, want to do.

To advertise the logs you should provide either a robots.txt or a Source Description at the location 
that you submit to Work Package 2.
See http://www.openarchives.org/rs/1.0/resourcesync for more information, 
or [contact us!](https://github.com/CLARIAH/virtuoso-quad-log/issues/new?Title=How+do+I+submit+my+data)
(The playground advertises the logs using the hidden folder .well-known)
