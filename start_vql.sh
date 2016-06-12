#!/bin/bash --

# Start a Docker container with the virtuoso quad logger.
# 
# 1. The virtuoso quad logger will poll the transaction logs of the Virtuoso instance 
# at the given host and port for changes in its Quad Store. 
#
# 2. The virtuoso quad logger uses the isql interactive interface to store incremental 
# change files as rdf-patch. See https://afs.github.io/rdf-patch/
#
# 3. The virtuoso quad logger enables the propagation of the changes through the
# Resource Sync Framework. See http://www.openarchives.org/rs/1.0/resourcesync
#

###############################################################################
# Set variables to reflect current conditions
#
# The directory used for serving Resource Sync files.
DATA_DIR="$PWD/data"
#
# The Virtuoso host name.
VIRTUOSO_ISQL_ADDRESS=192.168.99.100
#
# The Virtuoso isql port.
VIRTUOSO_ISQL_PORT=1111
#
# The Virtuoso user.
VIRTUOSO_USER=dba
#
# The Virtuoso password.
read -sp "Virtuoso password for the user '$VIRTUOSO_USER' " VIRTUOSO_PASSWORD
VIRTUOSO_PASSWORD=${VIRTUOSO_PASSWORD:-dba}
echo
#
# The time between consecutive runs of the quad logger.
# Default unit is seconds. Default value is 3600 (1 hour).
RUN_INTERVAL=20
#
# The location of transaction logs on the Virtuoso server.
# Default value is /usr/local/var/lib/virtuoso/db.
LOG_FILE_LOCATION=/usr/local/var/lib/virtuoso/db
#
# Should we insert stored procedures on the Virtuoso server automatically.
# The procedures that will be inserted all start with 'vql_'.
# Inserted procedures can be found with
#   SQL> SELECT P_NAME FROM SYS_PROCEDURES WHERE P_NAME LIKE 'DB.DBA.vql_*';
# If necessary they can be removed individually with
#   SQL> DROP PROCEDURE {P_NAME};
# Possible values: y|n
INSERT_PROCEDURES=y
#
## Dumps #############################
#
# Should we dump the initial state of the quad store.
# Possible values: y|n
DUMP_INITIAL_STATE=y
#
# Maximum amount of quads per dump file.
MAX_QUADS_IN_DUMP_FILE=500
#
# Should we dump the current state of the quat store and then exit.
# Possible values: y|n
DUMP_AND_EXIT=n
#
## Resource Sync ####################
#
# The base URL serving resources.
HTTP_SERVER_URL=http://foo.bar.com/rs/data
#
###############################################################################

echo -e "\n-- Starting virtuoso quad logger"
docker run -it --rm \
    -v $DATA_DIR:/datadir \
    -v $PWD/logs:/logs \
	--name vql \
    -e="VIRTUOSO_ISQL_ADDRESS=$VIRTUOSO_ISQL_ADDRESS" \
    -e="VIRTUOSO_ISQL_PORT=$VIRTUOSO_ISQL_PORT" \
    -e="VIRTUOSO_USER=$VIRTUOSO_USER" \
    -e="VIRTUOSO_PASSWORD=$VIRTUOSO_PASSWORD" \
    -e="RUN_INTERVAL=$RUN_INTERVAL" \
    -e="LOG_FILE_LOCATION=$LOG_FILE_LOCATION" \
    -e="INSERT_PROCEDURES=$INSERT_PROCEDURES" \
    -e="DUMP_INITIAL_STATE=$DUMP_INITIAL_STATE" \
    -e="MAX_QUADS_IN_DUMP_FILE=$MAX_QUADS_IN_DUMP_FILE" \
    -e="DUMP_AND_EXIT=$DUMP_AND_EXIT" \
    -e="HTTP_SERVER_URL=$HTTP_SERVER_URL" \
    bhenk/virtuoso-quad-log

