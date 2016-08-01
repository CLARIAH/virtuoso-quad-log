# virtuoso-quad-log

This *virtuoso-quad-log* repository harbors tools for propagating changes in RDF-data
kept in a [Virtuoso triple store](http://virtuoso.openlinksw.com/).

1. **quad_logger** generates logs of all initial, added, mutated or deleted quads in a
[Virtuoso quad store](http://virtuoso.openlinksw.com/rdf-quad-store/) in the
[RDF-patch](https://afs.github.io/rdf-patch/) format.
2. **resourcesync-generator** enables the synchronisation of these logs over the internet by means
of the [Resource Sync Framework](http://www.openarchives.org/rs/1.0/resourcesync).

The **example-virtuoso-server** is for demonstration purposes.

## Overview

<img src="/img/environment.pdf" alt="overview of quad logger environment"/>

![Overview](/img/environment.pdf)

## Documentation
Documentation of the software in this repository is split over several files.
- **README.md** (this file) contains a general introduction.
- **MOTIVATION.md** documents the background of this repository and motivates choices made.
- **DEPLOY.md** contains detailed instructions on the usage of the tools in this repository.
- **VIRTUOSO_CONFIG.md** communicates critical issues in your Virtuoso configuration.

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
