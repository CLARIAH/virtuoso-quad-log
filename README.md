# Quickstart

*(Skip to the Background section if you want to know what this code does)*

To play around with this image you need an openvirtuoso server. To help you get started you can create one using this image:

    docker run -d -p 8890:8890 --name virtuoso_server jauco/virtuoso-quad-log server

You can then browse to http://localhost:8890 and login with user: `dba` and password: `dba`.
You can upload data using the [quad store upload](http://localhost:8890/conductor/rdf_import.vspx)

Once you have a virtuoso container running you can run the quad-log like this:

	docker run -i -t --link virtuoso_server:virtuoso --name grabber jauco/virtuoso-quad-log

Or with any virtuoso server like this

	docker run -i -t --name grabber \
		-e="VIRTUOSO_ISQL_ADDRESS=127.0.01" \
		-e="VIRTUOSO_ISQL_PORT=1111" \
		-e="VIRTUOSO_USER=dba" \
		-e="VIRTUOSO_PASSWORD=dba" \
		jauco/virtuoso-quad-log

This initializes the container. You then rerun the container when needed:

	docker start -a grabber

# Background

> The availability of massive quantities of digital sources (textual, audio-visual and structured data) for research is
> revolutionizing the humanities. Top-quality humanities scholarship of today and tomorrow is therefore only possible
> with the use of sophisticated ICT tools. CLARIAH aims to offer humanities scholars a ‘Common Lab’ that provides them
> access to large collections of digital resources and innovative user-friendly processing tools, thus enabling them to
> carry out ground-breaking research to discover the nature of human culture.
>
> -- http://www.clariah.nl/en/voorstel/proposal-summary

This practically comes down to a lot of tooling and infrastructure to create, share and discover resources and research results.

To bring all this data together we group the tooling into workpackages (WP3, 4 and 5) and have a seperate workpackage to harvest
their data and link it together. As explained here: https://github.com/CLARIAH/wp2-interaction

# Approach

Each workpackage will be able to present their information encoded in the RDF datamodel (exact encodings have not yet been specified).
A crawler will read this information and store it's own database.
The individual workpackages are owner of the data, not the harvester.
This means that the harvester's database can be deleted and re-generated at will by re-harvesting from the providing data sources.

This repository details the harvesting protocol and its place within the other protocols.
It also contains a reference implementation for the open virtuoso rdf server.

# Available protocols

There are roughly two parts to the harvesting protocol.
The interaction between the harvester and the provider and the data format in which the data is encoded.

For the interaction we have evaluated the following approaches:

 * ~[OAI-PMH](https://www.openarchives.org/OAI/openarchivesprotocol.html)~ Focussed on metadata, not own data.
 * ~[Atom](https://tools.ietf.org/html/rfc4287)~ Features that we need such as marking an item as retracted are only available as extensions and finding tooling that supports the proper extensions is therefore hard. (*Supports atom* is not clear enough)
 * ~[Sitemaps](http://www.sitemaps.org/)~ Doesn't allow for retractions. Requires full re-indexing on every crawl.
 * [OAI-ResourceSync](https://www.openarchives.org/rs/toc) Seems to adress our usecase exactly according to the motivating examples. Is a bit large for our usecase, but our servers only need to deal with a subset and a client that fully implements the spec is already available.

If you know of other sync frameworks that fit the bill better: [Let us know!](https://github.com/CLARIAH/virtuoso-quad-log/issues/new?Title=I+know+a+better+(or+at+least+different)+interaction+protocol)

For the data encoding we settled on RDF as the information model, utilizing RDF-Quads for named graphs as detailed in the section Do Graphs need Naming? of [RDF Triples in XML](http://www.hpl.hp.com/techreports/2003/HPL-2003-268.pdf) but that still leaves a large amount of media types for encoding the data.
We have a few requirements on the media types:

 1. Handling of blank nodes
 2. Allowing both assertions and retractions to be modelled
 3. Allowing named graphs to be modelled
 4. You should be able to evaluate an assertion/retraction with minimal knowledge of the statements around it (because the files get big and will only grow) and preferably without having to query the current data store

A few notable requirements that we **don't** have are

 1. The document does not need to allow for a round trip (importing the generated document in the rdf store needs not be idempotent)
 2. The document does not need to live in the global context, but rather defines its own
    * if the node _:b1 is mentioned during the first crawl, a subsequent reference to it in a later crawl still refers to the same node
    * if two different logs (from different repositories) refer to _:b1 they refer to two different nodes

A few mediatypes and the requirement that they do not support are listed below

| media type | Blank nodes | assertions and retractions | named graph support | state dependency |
|------------|-------------|----------------------------|---------------------|------------------|
|[JSON-LD](https://www.w3.org/TR/json-ld/)                  | x |   | x | |
|[TRIG](https://www.w3.org/TR/trig/)                        | x |   | x | |
|[N3](https://www.w3.org/TeamSubmission/n3/)                | x |   | x | |
|[RDF Patch](http://afs.github.io/rdf-patch/)               | * | x | x | on the log, for tracking blank nodes |
|[TurtlePatch](https://www.w3.org/2001/sw/wiki/TurtlePatch) |   | x | x | |
|[Sparql]()                                                 | x | x | x | on the data store and allows arbitrary processing |
|[SparqlPatch](https://www.w3.org/2001/sw/wiki/SparqlPatch) | x | x | x | on the data store less arbitray processing, but still large runtime complexity of node matching |
|[LD Patch](https://www.w3.org/TR/ldpatch/)                 | x | x | x | on the data store, path following instead of node matching |

*) RDF patch only supports "store scoped" blank nodes.
Meaning that a specially encoded blank node in the document will always refer to the same node in the graph, but in between documents these identifiers will refer to different nodes.

We're therefore leaning towards RDF Patch, though that specification is stale after the LDP WG went for the LDpatch approach.


# Things to test and do (aka issues/tickets)

 - [x] offsets with multiple trx files (is the offset global or file specific. How to handle the offset after a checkpoint has run. What if multiple checkpoints have run in between grabs)
 - [x] non-default literals (stuff tagged as a date for example)
 - [x] literals vs hyperlinks
 - [x] blank nodes
 - [x] handle the fact that the last trx might still be changing (handling it by skipping the current transaction log)
 - [x] check if CheckpointAuditTrail is enabled when running this logger (cfg_item_value)
 - [x] multiple trx files (wrapper script)
 - [ ] escaping literals (at least newlines and quotes, check the nquads spec)
 - [ ] remove checkpoint statement before committing and deploying

 - [ ] try multiple insertion strategies and see if we can trigger all cases in the log (LOG_INSERT, LOG_INSERT_SOFT etc.)

 - [ ] make it stateful so we don't re-parse the same files over and over again
 - [ ] being able to go over the 50k rdf-patch files using resource-list indexes
 - [ ] make the update process atomic