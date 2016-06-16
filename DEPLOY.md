# Deployment of the virtuoso quad logger

## Where does it fit in

> ==Drawing of virtuoso-quad-logger amidst it's directly adjacent components: Virtuoso Quad Store
> and Source end of Resource Sync Framework.==

> ==Short introduction of the role of virtuoso-quad-logger in this chain.
> Links to the main technologies: virtuoso, rs-framework, rdf patch.==

## What it does

What exactly the virtuoso-quad-logger does can best be shown hands-on. Are you ready to take a
Docker dive?
Start a Docker daemon and then issue the following command to start the virtuoso-quad-logger
as a Docker container.


```
$ docker run bhenk/virtuoso-quad-log

  Running generate...
  No connection to isql -H 192.168.99.100 -S 1111
```
Oeps... At this time it didn't do anything special, except reporting that it could not get a connection
to the ISQL interface. This is what you get if there is no Virtuoso server at the default address.
So lets start a Virtuoso server under the default docker-machine...
```
$ docker run -it -p 8890:8890 -p 1111:1111 --name virtuoso_server --rm huygensing/virtuoso-quad-log server
  ...
  Server online at 1111 (pid 5)
```
... and start the virtuoso-quad-logger again, this time with a minimum of parameters. We will give
the container the name *quad_logger*, specify *data* as its data directory and give it an IP to
connect to.
```
$ docker run -it --rm  --name quad_logger -v $PWD/data:/datadir -e="VIRTUOSO_SERVER_HOST_NAME=$(docker-machine ip default)" bhenk/virtuoso-quad-log
```
```
    Running generate...
    Connected to isql -H 192.168.99.100 -S 1111
    Found 0 out of 8 required stored procedures.
    Inserting stored procedures...
    Inserted sql-proc/utils.sql
    Inserted sql-proc/dump_nquads.sql
    Inserted sql-proc/parse_trx.sql
    Executing dump...
    Dump reported in '/datadir/rdfdump-00002'
    # at checkpoint   20160615191707
    # dump started    2016-06-15 19:17:07.397727
    # dump completed  2016-06-15 19:17:08.492757
    # quad count      963
    # excluded graphs http://www.openlinksw.com/schemas/virtrdf# http://www.w3.org/ns/ldp# http://www.w3.org/2002/07/owl# http://localhost:8890/sparql http://localhost:8890/DAV/
    Syncing transaction logs starting from 20160615191707
    Published 3 resources under Resource Sync Framework in /datadir
    done. sleep 3600s
```
In a short time virtuoso quad logger

1. Connected to the Virtuoso ISQL interface at host *192.168.99.100* and port *1111*;
2. Inserted 8 procedures in Virtuoso/PL;
3. Dumped of all the quads in the Virtuoso quad store in the data directory;
4. Parsed the transaction logs;
5. Published all the files in the data directory under the Resource Sync Framework and
6. Went to sleep for an hour.

When it wakes up in an hour from now it will start with number 4. from the above list,
synchronize all
mutations that took place in the quad store since it's last visit, record these changes
in the rdf-patch format in files in the data directory and publsh a new listing of the
resources in the *resource-list.xml*. You should take a closer look at the data directory.
You should find the following files:
```
    __data
      |__ .well-known
      |  |__resourcesync
      |__capability-list.xml
      |__rdfdump-00001
      |__rdfdump-00002
      |__rdfpatch-20160615191707
      |__ ...
      |__rdfpatch-20190101123042
      |__resource-list.xml
```
You don't see the `rdfpatch-20190101123042` file? That's ok. Each time you, or someone else adds, deletes
or changes a quad on the quad store this will be reflected in the rdf-patch files in the data
directory as soon as virtuoso-quad-logger has made it's round. For now we have `rdfdump-*` files,
probably one `rdfpatch-*` file and 3 resource sync files: `.well-known/resourcesync`, a
`capability-list.xml` and a `resource-list.xml`. The resource sync files are here to enable
the discovery of your resources through the RS Framework. Your resources are the `rdfdump-*` and
`rdfpatch-*` files.

`rdfdump-00001` contains the initial state of your quad store at the time you started the
virtuoso-quad-logger. If you had a lot of quads in store there can be more files like that,
each filled with 100000 nquads, prefixed with a `+` sign. The header of each of these files
contains information about the dump.
```
# at checkpoint   20160615191707
# dump started    2016-06-15 19:17:07.397727
# quad count      0
+ <http://wordnet-rdf.princeton.edu/wn31/Allegheny-n#CanonicalForm> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "http://lemon-model.net/lemon#Form" <http://example.com/clariah> .
+ <http://wordnet-rdf.princeton.edu/wn31/Ataturk-n#CanonicalForm> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> "http://lemon-model.net/lemon#Form" <http://example.com/clariah> .
...

```
The last `rdfdump-*` file and the first `rdfpatch-*` file are identical. They both contain
a complete report on the dump.
```
# at checkpoint   20160615191707
# dump started    2016-06-15 19:17:07.397727
# dump completed  2016-06-15 19:17:08.492757
# quad count      963
# excluded graphs http://www.openlinksw.com/schemas/virtrdf# http://www.w3.org/ns/ldp# http://www.w3.org/2002/07/owl# http://localhost:8890/sparql http://localhost:8890/DAV/
```
For the time here and for ever after, virtuoso-quad-logger will follow the state of your quad store
and express this state as rdf-patches. Each `rdfpatch-XYZ` file corresponds to a `virtuosoXYZ.trx` file,
where `XYZ` is the timestamp of the Virtuoso transaction log. Additions are marked with a `+` sign,
deletions with a `-` sign and mutations are expressed in two rows, as a deletion & an addition.
```
# start: /usr/local/var/lib/virtuoso/db/virtuoso20190101123042.trx
+ <http://wordnet-rdf.princeton.edu/wn31/400461819-R> <http://wordnet-rdf.princeton.edu/ontology#translation> "saastaisesti"@fin <http://example.com/clariah> .
+ <http://wordnet-rdf.princeton.edu/wn31/ascend-v#1-v> <http://wordnet-rdf.princeton.edu/ontology#verb_frame_sentence> "The airplane is sure to %s "@eng <http://example.com/clariah> .
+ <http://wordnet-rdf.princeton.edu/wn31/201195306-V> <http://wordnet-rdf.princeton.edu/ontology#verb_group> <http://wordnet-rdf.princeton.edu/wn31/201195525-v> <http://example.com/clariah> .
- <http://wordnet-rdf.princeton.edu/wn31/American+gallinule-n#1-n> <http://wordnet-rdf.princeton.edu/ontology#tag_count> "0"^^<http://www.w3.org/2001/XMLSchema#integer> <http://example.com/clariah> .
- <http://wordnet-rdf.princeton.edu/wn31/Andromeda+glaucophylla-n#1-n> <http://wordnet-rdf.princeton.edu/ontology#tag_count> "0"^^<http://www.w3.org/2001/XMLSchema#integer> <http://example.com/clariah> .

```
Keeping all the dump and patch files and publishing them through the Resource Sync Framework
will not only enable third parties to catch up with the current state of your quad store.
It will also enable a journey through the past. Because, starting from the initial state
at the time of dump and computing the pluses and minuses until a certain point in time will
reconstruct the state of your quad store at that time.

## How to deploy

> ==Detailed instructions on deployment==