# How to deploy

The two main components **quad-logger** and the **resourcesync-generator** can both be deployed 
as Docker containers or as services 
under [Docker-compose](https://docs.docker.com/compose/). There are two `docker-compose.yml` files that should
get you started quickly. 

1. The `docker-compose-example-setup.yml` includes an example Virtuoso server and an
nginx http server, so it incorporates a complete environment  for the two main components.
You can use this experimental setup as a playground to watch the components at work.
2. The `docker-compose.yml` is a stub that you can use as a starting point
to incorporate the two components in your own environment. 

We will first inspect the example setup and see what the two components do. Than we will elaborate
on the environment variables which give you control over the exact behavior of the two components.


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

This will start 4 docker containers under the compose framework:

1. **some_virtuoso_server_with_data_preloaded** is an example Virtuoso server with over 900
quads preloaded in the Virtuoso quad store.
2. **the_quad_logger** connects to the example Virtuoso server and creates files
in the [RDF-patch](https://afs.github.io/rdf-patch/) format. Initially it will dump
all quads found in the Virtuoso quad store. Later on it will keep track of all changes that take 
place in the quad store. The quad logger writes these files to a docker volume named  `rdfdump`.
3. **resourcesync_generator** reads the docker volume `rdfdump`, packages the files
it finds there in zips and publishes the metadata as resource dumps under the
[Resource Sync Framework](http://www.openarchives.org/rs/1.0/resourcesync) in a
docker volume named `rdfpublish`.
4. **some_http_server** is a plain [nginx](https://hub.docker.com/_/nginx/) http server
that serves the contents of the docker volume `rdfpublish`.

If everything went well you should now be able to point your browser to
[http://192.168.99.100:8890/conductor/](http://192.168.99.100:8890/conductor/) 
and see the HTML based Administration Console of Virtuoso. The username and password
for this instance are `dba`, `dba`.

If you are not able to navigate to Virtuoso conductor,
verify the IP address of your docker machine. You can see the IP address of
your docker machine after typing `docker-machine ip` in your docker terminal.

After about 2 minutes the resourcesync generator will have dumped some files and metadata,
and these are available through the http server. 
Try [http://192.168.99.100:8085/resource-dump.xml](http://192.168.99.100:8085/resource-dump.xml)
for instance. Again, verify your docker machine IP address if this does not work.

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
the_quad_logger_1       | Dump reported in '/datadir/rdfdump-0000000097'
the_quad_logger_1       | # at checkpoint   20160802090158
the_quad_logger_1       | # dump started    2016-08-02 09:01:58.768298
the_quad_logger_1       | # dump completed  2016-08-02 09:01:59.885697
the_quad_logger_1       | # quad count      963
the_quad_logger_1       | # excluded graphs http://www.openlinksw ...
```
The original 963 quads in the Virtuoso quad store are now dumped to 97 files in the
directory `datadir`, which is mapped to the docker volume `rdfdump`. We set some
environment variables in the example docker-compose.yml to values that will 
demonstrate the working of the components. Of course writing 10 quads in each file
and packaging 10 such files in a zip is not a practical scenario.

After a while the resourcesync generator wakes up and finds the files produced by
the quad logger in it's directory `input` which is mapped to the 
docker volume `rdfdump`. It will start to compress the files into zip files and publish
resources and metadata in it's directory `output` which was mapped to the
docker volume `rdfpublish`.
```
resourcesync_generator_1    | Zipped 10 resources in /output/part_00000.zip
...
resourcesync_generator_1    | Zipped 9 resources in /output/zip_end_00000.zip
resourcesync_generator_1    | Published 10 dumps in /output/resource-dump.xml. See http://192.168.99.100:8085/resource-dump.xml
resourcesync_generator_1    | Published capability list. See http://192.168.99.100:8085/capability-list.xml
resourcesync_generator_1    | Published resource description. See http://192.168.99.100:8085/.well-known/resourcesync
resourcesync_generator_1    | sleep 60.
```
A resource sync destination is now capable of discovering the packaged resources and metadata
by navigating to 
[http://192.168.99.100:8085/.well-known/resourcesync](http://192.168.99.100:8085/.well-known/resourcesync)
and following the path down to the individual packaged content.

If you insert new triples into the Virtuoso quad store these will be picked up by the quad logger
and written to rdf-patch files. Once in the dump directory they are discovered by 
resourcesync generator and packaged into zip files. The resourcesync generator also
cleans up the dump directory once in a while. It removes the files that where packeged in 
'complete zips', that is zip files that have reached the maximum amount of files.

## Environment variables for quad-logger
The following environment variables can be set on the **quad-logger**. Environment variables
can be set in the `docker-compose.yml` files under the **environment:** heading.

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
reached. Default value is `1111`.

**VIRTUOSO_DB_USER** - The username of the Virtuoso user. Default value is `dba`.

**VIRTUOSO_DB_PASSWORD** - The password of the Virtuoso user. Default value is `dba`.

**LOG_FILE_LOCATION** - The location of transaction logs on the Virtuoso server.
Default value is `/usr/local/var/lib/virtuoso/db`.

<a id="DATA_DIR"></a>**DATA_DIR** - The directory for (temporary) storage of the rdf-patch files. 
Default value is `/datadir`.

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

**MAX_QUADS_PER_DUMP_FILE** - The maximum number of quads that should go into one 
dump file. On average 100000 quads will give file sizes of approximately 12.5 MB.
Default value is `100000`.

**EXCLUDED_GRAPHS** - Space-separated list of graph iris that are excluded from the dump.
As per default the following graphs are excluded from the dump:

- http://www.openlinksw.com/schemas/virtrdf#
- http://www.w3.org/ns/ldp#
- http://www.w3.org/2002/07/owl#
- http://localhost:8890/sparql
- http://localhost:8890/DAV/

## Environment variables for resourcesync-generator
The following environment variables can be set on the **resourcesync-generator**. 
Environment variables
can be set in the `docker-compose.yml` files under the **environment:** heading.

**RUN_INTERVAL** - The time between consecutive runs of the generator. Value can be 
NUMBER[SUFFIX], where SUFFIX is

- s for seconds (the default)
- m for minutes.
- h for hours.
- d for days.

Default value is `3600` (1 hour).

**RESOURCE_DIR** - The directory where rdf-patch files can be found. This should be the
same directory as the dump directory of the quad-logger 
(See [DATA_DIR](#DATA_DIR)). Under docker-compose the quad-logger DATA_DIR and the
resourcesync-generator RESOURCE_DIR should point to the same docker volume.
Default value is `/input`.

**PUBLISH_DIR** - The directory where resource dump files and metadata are published.
This directory should be accessible and served by the Http server.
Default value is `/output`.

**HTTP_SERVER_URL** - `(Required)` The public URL pointing to directory being served by 
the Http server. (See PUBLISH_DIR). This URL is used to generate links in the resource sync xml files.

**MAX_FILES_IN_ZIP** - The maximum number of files that should go into one zip file.
Default value is `100`.

**WRITE_SEPARATE_MANIFEST** - Write a separate resourcedump manifest to PUBLISH_DIR. 
This file is the same as the one included in each zip file under the name `manifest.xml`.
The separate manifest files wil have names like `manifest_xxx_xxx.xml`, where
`xxx_xxx` is the same as the basename of the zip file it accompanies without 
the extension `zip`. For instance 'manifest_part_00004.xml' accompanies 'part_00004.zip'.
Possible values: `y|n`. Default value is `y`.

**MOVE_RESOURCES** - Move the zipped resources from RESOURCE_DIR to PUBLISH_DIR or simply 
delete them from RESOURCE_DIR. Only rdf-patch files that are packaged into
`part_xxxxx.zip` files are affected. Rdf-patch files that are provisionally packaged in the
`zip_end_xxxxx.zip` file will remain in RESOURCE_DIR.
Possible values: `y|n`. Default value is `n`.

## Connect to a production Virtuoso server

To connect the logger to a production virtuoso server, you can edit the environment variables in 
the `docker-compose.yml`. If you do not want the nginx as HTTP-server, comment out that service
near the top of the file. Build the images with

	docker-compose build

After a successful build you can launch the services with

	docker-compose up
	
You should now be able to see files created in `dumpdir` and `publishdir`. 

In order to enable third parties to synchronize with the state of your Virtuoso instance,
the directory `publishdir` should be served on a public URL.
	
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
Error: 'rdfdump-*' files found in '/datadir'. Remove 'rdfpatch-*' and 'rdfdump-*' files before dumping.
```
**origin:** _the_quad_logger_

**cause:** _the_quad_logger_ wants to do a fresh dump (`DUMP_INITIAL_STATE=y` and
the file `rdfdump-9999999999` is missing or invalid) but there are old 
`rdfpatch-*` and/or `rdfdump-*` files in the directory or volume `rdfdump`.

**remedy:**
Remove `rdfpatch-*` and `rdfdump-*` files from the dump directory.

### No handshake

**message:**
```
Error: No resource_handshake found. Not interfering with status quo of published resources.
```

**origin:** _resourcesync_generator_

**cause:** The handshake file `started_at.txt` is missing from `dump_dir`. The
_resourcesync_generator_ cannot verify synchronized action with _the_quad_logger_
and is maintaining status quo.

**remedy:**
If this happens when _the_quad_logger_ has not started completely, this only
 indicates that _the_quad_logger_ has not set a handshake file yet. If
the phenomenon persists, this indicates a serious failure. In this case:
completely empty `dump_dir`. This will cause _the_quad_logger_ to start a new
dump and subsequent patches. _resourcesync_generator_ will follow by emptying 
the `publish_dir` and start synchronizing afresh.

**message:**
```
Error: No publish_handshake found and /output not empty. Not interfering with status quo of published resources.
```

**origin:** _resourcesync_generator_

**cause:** The handshake file `started_at.txt` is missing from `publish_dir`
and the directory `publish_dir` is not empty. The
_resourcesync_generator_ cannot verify synchronized action with _the_quad_logger_
and is maintaining status quo.

**remedy:**
Same as above but this time you also have to completely empty `publish_dir` as well.
Best to stop the two services _the_quad_logger_ and _resourcesync_generator_,
empty both `dump_dir` and `publish_dir` and start both services again.










