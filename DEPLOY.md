# How to deploy

The two main components **quad-logger** and the **resourcesync-generator** can both be deployed 
as Docker containers or as services 
under [Docker-compose](https://docs.docker.com/compose/). There are two ```docker-compose.yml``` files that should
get you started quickly. 

1. The ```docker-compose-example-setup.yml``` includes an example Virtuoso server and an
nginx http server, so it incorporates a complete environment  for the two main components.
You can use this experimental setup as a playground to watch the components at work.
2. The ```docker-compose.yml``` is a stub that you can use as a starting point
to incorporate the two components in your own environment. 

We will first inspect the example setup and see what the two components do. Than we will elaborate
on the environment variables which give you control over the exact behavior of the two components.


## Sparking up a playground

Once you have [Docker-compose installed](https://docs.docker.com/compose/install/) on your system
you can spark up the playground. Open a docker terminal and
navigate to the root directory where
you downloaded or cloned the virtuoso-quad-log repository. At te command line type:
```
docker-compose -f docker-compose-example-setup.yml build
```
This will build the docker images needed in the next step. Still in the docker terminal type:
```
docker-compose -f docker-compose-example-setup.yml up
```

This will start 4 docker containers under the compose framework:

1. **some_virtuoso_server_with_data_preloaded** is an example Virtuoso server with over 900
quads pre loaded in the Virtuoso quad store.
2. **the_quad_logger** connects to the example Virtuoso server and creates files
in the [RDF-patch](https://afs.github.io/rdf-patch/) format. Initially it will dump
all quads found in the Virtuoso quad store. Later on it will keep track of all changes that take 
place in the quad store. The quad logger writes these files to a docker volume named 
```rdfdump```.
3. **resourcesync_generator** reads the docker volume ```rdfdump```, packages the files
it finds there in zips and publishes the metadata as resource dumps under the
[Resource Sync Framework](http://www.openarchives.org/rs/1.0/resourcesync) in a
docker volume named ```rdfdumpwithresourcesync```.
4. **some_http_server** is a plain [nginx](https://hub.docker.com/_/nginx/) http server
that serves the contents of the docker volume ```rdfdumpwithresourcesync```.

If everything went well you should now be able to point your browser to
[http://192.168.99.100:8890/conductor/](http://192.168.99.100:8890/conductor/) 
and see the HTML based Administration Console of Virtuoso. The username and password
for this instance are ```dba```, ```dba```.

If you are not able to navigate to Virtuoso conductor,
verify the IP address of your docker machine. You can see the IP address of
your docker machine after typing ```docker-machine ip``` in your docker terminal.

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
inserted several stored procedures. These procedures all start with ```vql_*```. It than 
starts to execute a dump. This will cause Virtuoso to set checkpoints, once at the start
of the dump, once the dump has finished. After finishing the dump quad logger reports 
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
directory ```datadir```, which is mapped to the docker volume ```rdfdump```. We set some
environment variables in the example docker-compose.yml to values that will 
demonstrate the working of the components. Of course writing 10 quads in each file
and packaging 10 such files in a zip is not a practical scenario.

After a while the resourcesync generator wakes up and finds the files produced by
the quad logger in it's directory ```input``` which is mapped to the 
docker volume ```rdfdump```. It will start to compress the files into zip files and publish
the metadata in it's directory ```output``` which was mapped to the
docker volume ```rdfdumpwithresourcesync```.
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

## Environment variables of quad-logger
The following environment variables can be set on the **quad-logger**. Environment variables
can be set in the ```docker-compose.yml``` files under **environment:** heading.







