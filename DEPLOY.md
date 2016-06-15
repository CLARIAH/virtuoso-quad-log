# Deployment of the virtuoso quad logger

## What it does

The virtuoso quad logger can be started as a Docker container.


```
$ docker run bhenk/virtuoso-quad-log

  Running generate...
  No connection to isql -H 192.168.99.100 -S 1111
```
At this time it didn't do anything special, except reporting that it could not get connection
to the ISQL interface. This is what you get if there is no Virtuoso server at the default address.
So lets start a Virtuoso server under the default docker-machine...
```
$ docker run -it -p 8890:8890 -p 1111:1111 --name virtuoso_server --rm huygensing/virtuoso-quad-log server
```
```
  ...
  Server online at 1111 (pid 5)
```
... and start the virtuoso quad logger again, this time with a minimum of parameters. We will give
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

When it wakes up it will start with number **4.** from the above list, synchronize all
mutations that took place in the quad store since it's last visit, record these changes
in the rdf-patch format in files in the data directory and publsh a new listing of the
resources in the resource-list.



