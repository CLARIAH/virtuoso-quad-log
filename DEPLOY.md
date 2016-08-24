# How to deploy

The **quad-logger**, the **graph-splitter** and the **resourcesync-generator** can be deployed 
as Docker containers or services 
under [Docker-compose](https://docs.docker.com/compose/). There are two `docker-compose.yml` files 
that should get you started quickly. 

1. The `docker-compose-example-setup.yml` includes an example Virtuoso server and an
nginx http server, so it incorporates a complete environment  for the chain of components.
You can use this experimental setup as a playground and watch the components at work.
2. The `docker-compose.yml` is a stub that you can use as a starting point
to incorporate the services in your own environment. 

We will first inspect the example setup and see what the components do. Than we will elaborate
on the environment variables which give you control over the exact behavior of the components.


## Sparking up a playground

Once you have [Docker-compose installed](https://docs.docker.com/compose/install/) on your system
you can spark up the playground. Open a docker terminal and
navigate to the root directory where
you downloaded or cloned the virtuoso-quad-log repository. At the command line type:
```
docker-compose -f docker-compose-example-setup.yml build
```
This will build the docker images needed in the next step. Still in the docker terminal type:
```
docker-compose -f docker-compose-example-setup.yml up
```

This will start 5 docker containers under the compose framework:

1. **some_virtuoso_server_with_data_preloaded** is an example Virtuoso server with over 1000
quads preloaded in the Virtuoso quad store.
2. **the_quad_logger** connects to the example Virtuoso server and creates files
in the [RDF-patch](https://afs.github.io/rdf-patch/) format. Initially it will dump
all quads found in the Virtuoso quad store. Later on it will keep track of all changes that take 
place in the quad store. The quad logger writes these files to the docker volume `stash1`.
3. **the_graph_splitter** splits up the rdf-patch files found in `stash1` along graph iri 
of the N-Quads and will store them again as rdf-patch files in docker volume `stash2`, 
grouped in folders who's names are the base64 translation of the graph iri.
4. **resourcesync_generator** reads the docker volume `stash2`, packages the files
it finds there in zips and publishes the metadata as resource dumps under the
[Resource Sync Framework](http://www.openarchives.org/rs/1.0/resourcesync) in a
docker volume named `stash3`.
4. **some_http_server** is a plain [nginx](https://hub.docker.com/_/nginx/) http server
that serves the contents of the docker volume `stash3`.

If everything went well you should now be able to point your browser to
[http://192.168.99.100:8890/conductor/](http://192.168.99.100:8890/conductor/) 
and see the HTML based Administration Console of Virtuoso. The username and password
for this instance are `dba`, `dba`.

If you are not able to navigate to Virtuoso conductor,
verify the IP address of your docker machine. You can see the IP address of
your docker machine after typing `docker-machine ip` in your docker terminal.

After about 2 minutes the resourcesync generator will have dumped some files and metadata,
and these are available through the http server. 
Try [http://192.168.99.100:8085/aW5mbzpzcGVjaWFsCg==/capability-list.xml](http://192.168.99.100:8085/aW5mbzpzcGVjaWFsCg==/capability-list.xml)
for instance. The `aW5mbzpzcGVjaWFsCg==` part in this path is the base64 translation of
`info:special`, the graph iri of a particular graph in the `virtuoso_server_with_data_preloaded`.
The normal entry for Resourcesync destinations would be 
[http://192.168.99.100:8085/.well-known/resourcesync](http://192.168.99.100:8085/.well-known/resourcesync).
Again, verify your docker machine IP address if this does not work and adjust the
_resourcesync_generator_ environment variable HTTP_SERVER_URL accordingly.

## What it does

If we inspect the logs that are printed to the docker console we can follow what the 
components are doing. First the quad logger tries to connect to the ISQL interface of Virtuoso:
```
the_quad_logger_1       | Running generate...
the_quad_logger_1       | No connection to isql -H virtuoso-source -S 1111
the_quad_logger_1       | generate failed. sleep 60
```
This is because the Virtuoso server is still starting up and not yet accepting connections.
The second time around it has more luck.
```
the_quad_logger_1       | Running generate...
the_quad_logger_1       | Connected to isql -H virtuoso-source -S 1111
the_quad_logger_1       | Found 0 out of 9 required stored procedures.
the_quad_logger_1       | Inserting stored procedures...
...
the_quad_logger_1       | Executing dump...
```
The first time the quad logger connects to the interactive interface of Virtuoso it will
insert several stored procedures. These procedures all start with `vql_*`. It than 
starts to execute a dump. This will cause Virtuoso to set checkpoints, once at the start
of the dump, once at the end of the dump. After finishing the dump the quad logger reports 
what it has done.
```
the_quad_logger_1       | Dump reported in '/output/rdfpatch-0d000000000116'
the_quad_logger_1       | # at checkpoint   20160802090158
the_quad_logger_1       | # dump started    2016-08-02 09:01:58.768298
the_quad_logger_1       | # dump completed  2016-08-02 09:01:59.885697
the_quad_logger_1       | # quad count      1584
the_quad_logger_1       | # file count      18
```
The original 1584 quads in the Virtuoso quad store are now dumped to several files in the
directory `output`, which is mapped to the docker volume `stash1`. We set some
environment variables in the `docker-compose-example-setup.yml` to values that will 
demonstrate the working of the components. Of course writing 10 quads in each file
and packaging 10 such files in a zip is not a practical scenario.

After a while the graph splitter wakes up and finds the files produced by the quad logger
in it's directory `input` which is mapped to the docker volume `stash1`.
It will subdivide the files along graph iri and move them to folders
in the directory `output` which is mapped to the docker volume `stash2`. The folder
names in the `output` directory are the base64 translation of the graph iris.
```
the_graph_splitter_1        | Filed 1158 N-Quads during this run
```

After a while the resourcesync generator wakes up and finds the files and folders produced by
the graph splitter in it's directory `input` which is mapped to the 
docker volume `stash2`. It will start to compress the files into zip files and publish
resources and metadata in it's directory `output` which was mapped to the
docker volume `stash3`.
```
resourcesync_generator_1    | Published new resource description. See http://192.168.99.100:8085/.well-known/resourcesync
resourcesync_generator_1    | sleep 60.
```
A resource sync destination is now capable of discovering the packaged resources and metadata
by navigating to 
[http://192.168.99.100:8085/.well-known/resourcesync](http://192.168.99.100:8085/.well-known/resourcesync)
and following the path down to the individual packaged content.

If you insert new triples into the Virtuoso quad store these will be picked up by the quad logger
and written to rdf-patch files. Once in the output directory they are discovered by 
the graph splitter, subdivided in folders per graph, after which the resourcesync generator packages this content
into zip files. Both graph splitter and resourcesync generator 
clean up their respective input directories once files have been processed. The resourcesync generator only
removes files that where packeged in 
'definitive zips', that is zip files that have reached the maximum amount of files as specified by the
environment variable MAX_FILES_COMPRESSED.

This is in brief what the chain of processors does. In the next paragraphs we will describe each module of 
the processing chain in more detail.

## The quad-logger

Generates logs of all initial, added, mutated or 
deleted [N-Quads](https://www.w3.org/TR/n-quads/) in a
[Virtuoso quad store](http://virtuoso.openlinksw.com/rdf-quad-store/) in the
[RDF-patch](https://afs.github.io/rdf-patch/) format.

Initally it will insert several stored procedures in the Virtuoso server that will do the work on that part.
The names of these stored procedures all start with `vql_*`. 

Then it will dump all N-Quads found in the 
Virtuoso quad store into files in it's output directory. The names of the files of the initial dump are of the pattern
`rdf_out_00000000000000-xxxxxxxxxxxxxx`, where `xxxxxxxxxxxxxx` is a 14 digit serial number. 
After that it will repeatedly
poll the Virtuoso server for new transaction logs and, if found, process mutations found in these transaction logs
into rdf-patch files, who's names have the pattern `rdf_out_yyyymmddhhmmss-xxxxxxxxxxxxxx`, where `yyyymmddhhmmss` 
is a timestamp corresponding to local time of the machine on which the procedure is running.
[VIRTUOSO_CONFIG.md](/VIRTUOSO_CONFIG.md) details
how to configure Virtuoso to make this all work.

### Environment variables for quad-logger
The following environment variables can be set on the **quad-logger**. Environment variables
can be set in the `docker-compose.yml` under the heading **environment**.

**RUN_INTERVAL** - The time between consecutive runs of the quad logger. Value can be 
NUMBER[SUFFIX], where SUFFIX is

- s for seconds (the default)
- m for minutes.
- h for hours.
- d for days.

Default value is `3600` (1 hour).

**VIRTUOSO_HOST_NAME** - `(Required)` The IP address or host name of the Virtuoso server. If the Virtuoso
server is also deployed as a service under docker-compose this can be the name or alias of 
that server.

**VIRTUOSO_ISQL_PORT** - The port of the Virtuoso server where the Interactive SQL interface can be
reached.  
Default value is `1111`.

**VIRTUOSO_DB_USER** - The username of the Virtuoso user.  
Default value is `dba`.

**VIRTUOSO_DB_PASSWORD** - The password of the Virtuoso user.  
Default value is `dba`.

**LOG_FILE_LOCATION** - The location of transaction logs on the Virtuoso server.  
Default value is `/usr/local/var/lib/virtuoso/db`.

**DUMP_DIR** - The directory for (temporary) storage of the rdf-patch files.  
Default value is `/output`.

**INSERT_PROCEDURES** - Should stored procedures be automatically inserted on the 
Virtuoso server. The procedures that will be inserted all start with 'vql_'.
Inserted procedures can be found with
```
SQL> SELECT P_NAME FROM SYS_PROCEDURES WHERE P_NAME LIKE 'DB.DBA.vql_*';
```
If necessary they can be removed individually with
```
SQL> DROP PROCEDURE {P_NAME};
```
Possible values: `y|n`. Default value is `n`.

**DUMP_INITIAL_STATE** - Dump the current state of the quad store (execute the dump routine).
No transactions should take place during execution of the dump. 
On average the dump routine will take 1 hour per 100 million quads execution time.
If a dump has been executed previously and 
was completed successfully, this parameter has no effect.  
Possible values: `y|n`. Default value is `y`.

**DUMP_AND_EXIT** - Dump the current state of the quad store and then exit.  
Possible values: `y|n`. Default value is `n`.

**MAX_QUADS_PER_FILE** - The maximum number of quads that should go into one 
output file. On average 100000 quads will give file sizes of approximately 12.5 MB.  
Default value is `100000`.

**EXCLUDED_GRAPHS** - Space-separated list of graph iris that are excluded from the dump.
As per default the following graphs are excluded from the dump:

- http://www.openlinksw.com/schemas/virtrdf#
- http://www.w3.org/ns/ldp#
- http://www.w3.org/2002/07/owl#
- http://localhost:8890/sparql
- http://localhost:8890/DAV/

## The graph-splitter

Splits the rdf-patch files in it's input directory over graph iri and stores them in folders
in it's output directory. 

Files in the output directory are stored in separate folders per graph iri. The names of these folders are 
the base64 translation of the graph iri. The graph splitter is an optional part of the processing chain.
If left out the output directory of the quad-logger should be made the input directory of the 
resourcesync-generator.

### Environment variables for graph-splitter
The following environment variables can be set on the **graph-splitter**. 
Environment variables
can be set in the `docker-compose.yml` under the heading **environment**.

**RUN_INTERVAL** - The time between consecutive runs of the splitter. Value can be 
NUMBER[SUFFIX], where SUFFIX is

- s for seconds (the default)
- m for minutes.
- h for hours.
- d for days.

Default value is `3600` (1 hour).

**SOURCE_DIR** - The directory where rdf-patch files for processing are found, which coincides with the output
directory of the quad-logger.  
Default value is `/input`.

**SINK_DIR** - The directory where rdf-patch files after processing are stored.  
Default value is `/output`.

## The resourcesync-generator

Enables the synchronization of the produced resources over the 
internet by means
of the [Resource Sync Framework](http://www.openarchives.org/rs/1.0/resourcesync).

If rdf-patch files are split over graph iri, for each graph iri a separate `capability-list.xml` will be
produced. 

### Environment variables for resourcesync-generator
The following environment variables can be set on the **resourcesync-generator**. 
Environment variables
can be set in the `docker-compose.yml` under the heading **environment**.

**RUN_INTERVAL** - The time between consecutive runs of the generator. Value can be 
NUMBER[SUFFIX], where SUFFIX is

- s for seconds (the default)
- m for minutes.
- h for hours.
- d for days.

Default value is `3600` (1 hour).

**SOURCE_DIR** - The directory where rdf-patch files can be found. This should coincide with the output
directory of the graph splitter or, if no graph-splitter is used, with the output directory
of the quad-logger.  
Default value is `/input`.

**SINK_DIR** - The directory where resource dump files and metadata are published.
This directory should be accessible and served by the Http server.  
Default value is `/output`.

**HTTP_SERVER_URL** - `(Required)` The public URL pointing to directory being served by 
the Http server. (See SINK_DIR). This URL is used to generate links in the resource sync xml files.

**BUILDER_CLASS** - The Python class responsible for compression of the rdf-patch files. Default this is
a class that compresses in the g-zip format. If you want to provide a builder class, this class should
have a constructor compatible with the constructor of class `Synchronizer` and support the method
`publish`.
Apart from duck typing you can use the abstract base class `Synchronizer` as a starting point. 
See [synchronizer.py](/resourcesync-generator/oai-rs/synchronizer.py).  
Default value is `zipsynchronizer.ZipSynchronizer`.

**MAX_FILES_COMPRESSED** - The maximum number of files that should go into one compression file.  
Default value is `1000`.

**WRITE_SEPARATE_MANIFEST** - Write a separate resourcedump manifest in SINK_DIR. 
This file is the same as the one included in each compressed file under the name `manifest.xml`.
The separate manifest files wil have names like `manifest_xxx_xxx.xml`, where
`xxx_xxx` is the same as the basename of the zip file it accompanies without 
the extension. For instance 'manifest_part_def_00004.xml' accompanies 'part_def_00004.zip'.  
Possible values: `y|n`. Default value is `y`.

**MOVE_RESOURCES** - Move the resources from SOURCE_DIR to SINK_DIR or simply 
delete them from SOURCE_DIR after they have been packaged. Only rdf-patch files that are packaged into
`part_def_xxxxx` files are affected. Rdf-patch files that are provisionally packaged in the
`part_end_xxxxx` file will remain in SOURCE_DIR.  
Possible values: `y|n`. Default value is `n`.

## Connect to a production Virtuoso server

To connect the logger to a production virtuoso server, you can edit the environment variables in 
the `docker-compose.yml`. If you do not want the nginx as HTTP-server, comment out that service. 
Build the images with

	docker-compose build

After a successful build you can launch the services with

	docker-compose up
	
You should now be able to see files created in the intermediate storage locations, the output directories
of the various chained modules. 

In order to enable third parties to synchronize with the state of your Virtuoso instance,
the output directory of the resourcesync-generator should be served on a public URL.
	
## Error messages

Below is a list of error messages you might see in the logs after launching.


### No connection
**message:**
```
No connection to isql -H {address} -S {port}
```
**origin:** _the_quad_logger_

**cause:** _the_quad_logger_ cannot connect to the Virtuose server. This could be a temporary issue.

**remedy:**
If the error persists over several runs of _the_quad_logger_ make sure that address
 (VIRTUOSO_HOST_NAME) and port (VIRTUOSO_ISQL_PORT)
as set in the environment variables of _the_quad_logger_ are correct.
 
Your firewall may be blocking the ISQL port of your Virtuoso server. (The default port number
for Virtuoso ISQL is 1111.) Make sure address and port can be reached
from _the_quad_logger_. You might test the connection with the command `nc`.
```
nc -vz {address} {port}
```

### Undefined procedure
**message:**
```
*** Error 42001: [Virtuoso Driver][Virtuoso Server]SR185: Undefined procedure DB.DBA.read_log.
```
**origin:** _the_quad_logger_

**cause:** Your Virtuoso instance is missing the built-in function `read_log()`. This function
is missing from older versions of Virtuoso and is essential for correct functioning of
 _the_quad_logger_.

**remedy:**
Upgrade to a newer version of Virtuoso.

### Old dump or patch files

**message:**
```
Error: 'rdfpatch-*' files found in '/datadir'. Remove 'rdfpatch-*' and 'rdfdump-*' files before dumping.
```
**origin:** _the_quad_logger_

**cause:** _the_quad_logger_ wants to do a fresh dump (`DUMP_INITIAL_STATE=y` and
the file `rdfdump_info.txt` is missing or invalid) but there are old 
`rdfpatch-*` files in the output directory or volume `stash1`.

**remedy:**
Remove `rdfpatch-*` files from the dump directory.

### No handshake

**message:**
```
Error: No source handshake found. Not interfering with status quo.
```

**origin:** _the_graph_splitter_ or _resourcesync_generator_

**cause:** The handshake file `started_at.txt` is missing from the input directory. The
service cannot verify synchronized action with the previous service in the chain
and is maintaining status quo.

**remedy:**
If this happens when the previous service in the chain has not started completely, this only
 indicates that the previous service has not set a handshake file yet. If
the phenomenon persists, this indicates a serious failure. In this case:
completely empty the output directory of _the_quad_logger_ (`stash1`). This will cause _the_quad_logger_ to start a new
dump and subsequent patches. _the_graph_splitter_ and _resourcesync_generator_ will follow by emptying 
their output directories and start synchronizing afresh.

**message:**
```
Error: No publish_handshake found and /output not empty. Not interfering with status quo.
```

**origin:** _the_graph_splitter_ or _resourcesync_generator_

**cause:** The handshake file `started_at.txt` is missing from the output directory
and the output directory is not empty. The _the_graph_splitter_ or
_resourcesync_generator_ cannot verify synchronized action with the previous service in the chain
and is maintaining status quo.

**remedy:**
Same as above: completely empty the output directory of _the_quad_logger_ (`stash1`). 
This will cause _the_quad_logger_ to start a new
dump and subsequent patches. _the_graph_splitter_ and _resourcesync_generator_ will follow by emptying 
their output directories and start synchronizing afresh.

### Mismatch in N-Quad count

**message:**
```
WARNING: Total of exported N-Quads not equal to total of filed N-Quads.     
 	exported: 1158, filed: 1157, difference: 1
```

**origin:** _the_graph_splitter_

**cause:** The files `vql_nquads_count.txt` in the _the_graph_splitter_ directories input and output 
give different readings of the amount of N-Quads that have been exported by _the_quad_logger_ and the
amount of N-Quads that have been filed by _the_graph_splitter_ respectively.

**remedy:**
This could be a temporary issue; the warning should go away after another run of _the_graph_splitter_. If not,
you can either live with it (in the above example you miss one N-Quad) or start from scratch by
emptying the output directory of _the_quad_logger_ (`stash1`). `# rm vql_* rdf_out_*`

### Mismatch in file count

**message:**
```
INFO: File count out of sync: exported files=19, filed files=2
WARNING: Accounting files is out of sync. Files filed: 2, resources synchronized 19
```

**origin:** _the_graph_splitter_ or _resourcesync_generator_

**cause:** The files `vql_files_count.txt` in the input and output directories
give different readings of the amount of files that have been exported, subdivided or packaged
by _the_quad_logger_, _the_graph_splitter_ and/or _resourcesync_generator_

**remedy:**
This could be a temporary issue; the warning should go away after another run of the reporting module, or at
least when the system has completely come to rest and all modules have finished processing resources.
If not, start from scratch by emptying the output directory of _the_quad_logger_ (`stash1`). 
`# rm vql_* rdf_out_*`
