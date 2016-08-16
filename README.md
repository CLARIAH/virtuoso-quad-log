# Virtuoso Quad Logger

- The components in this repository are intended to be used by developers and system administrators.
- In case of questions [contact](https://github.com/CLARIAH/virtuoso-quad-log/issues/new) the CLARIAH team.
 
____

The RDF data model can be used to share and distribute information from a wide variety of sources 
and has [distinguished advantages](https://www.w3.org/RDF/advantages.html) over other data models.
Keeping track of state and changes in dispersed data stores and propagating state and changes
to other data stores or a central hub
is out of scope of the data model it self. Reporting the initial state of a data store, keeping
track of changes during the life of the store and publishing this state and these changes to the
outside world in accordance with a well-described protocol is the subject of this repository.


This *virtuoso-quad-log* repository harbors a chain of tools for propagating and publishing 
changes in RDF-data
that are kept in a [Virtuoso triple store](http://virtuoso.openlinksw.com/). Essential components 
in this chain are:

1. **quad-logger** generates logs of all initial, added, mutated or 
deleted [N-Quads](https://www.w3.org/TR/n-quads/) in a
[Virtuoso quad store](http://virtuoso.openlinksw.com/rdf-quad-store/) in the
[RDF-patch](https://afs.github.io/rdf-patch/) format.
2. **graph-splitter** will subdivide the N-Quads in these rdf-patch files into 
other rdf-patch files grouped by graph iri. If a subdivision along graph iri is not nescesary 
or not wanted, the graph-splitter can be left out of the chain.
3. **resourcesync-generator** enables the synchronization of the produced resources over the 
internet by means
of the [Resource Sync Framework](http://www.openarchives.org/rs/1.0/resourcesync).

The **example-virtuoso-server** is for reference and demonstration purposes. The tools can be deployed as
services under [Docker-compose](https://docs.docker.com/compose/).

## Overview

![Overview](/img/environment2.png)

<i><small>The above image shows the quad-logger, the graph-splitter and the resourcesync-generator 
in their environment.
The Virtuoso server is instructed to log its transactions in log files.  
The `quad-logger` interacts
with the Virtuoso server by means of the Interactive SQL interface. It reads the 
transaction logs and transforms them to rdf-patch formatted files.  
The `graph-splitter`
will subdivide the N-Quads in these rdf-patch files into other rdf-patch files grouped 
in folders per graph iri. Folder names are the base64 translation of the graph iri.
If a subdivision along graph iri is not nescesary or not wanted, 
the graph-splitter can be left out of the chain.  
The `resourcesync-generator`
bundles the rdf-patch files in zip-files and publishes them in accordance with the
Resource Sync Framework. In case N-Quads are subdivided along graph iri, each folder will
be represented as a distinct set of resources.  
The quad-logger, the graph-splitter and the resourcesync-generator 
can be deployed as
Docker containers. Here they are deployed as docker-compose services. 
The Http server and the Virtuoso server can also be deployed as docker-compose service.</small></i>

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
the docker-compose.yml and launch using

	docker-compose build
	docker-compose up

This also launches a local nginx which you might, or might not, want to do.

To advertise the logs you should provide either a robots.txt or a Source Description at the location 
that you submit to Work Package 2.
See http://www.openarchives.org/rs/1.0/resourcesync for more information, 
or [contact us!](https://github.com/CLARIAH/virtuoso-quad-log/issues/new?Title=How+do+I+submit+my+data)
(The playground advertises the logs using the hidden folder .well-known)
