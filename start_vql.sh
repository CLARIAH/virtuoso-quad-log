#!/bin/bash --

# # Start a Docker container with the virtuoso quad logger.
# #
# # 1. The virtuoso quad logger will dump the current state of the Quad Store as rdf-patch.
# # See https://afs.github.io/rdf-patch/
# #
# # 2. The virtuoso quad logger will poll the transaction logs of the Virtuoso instance
# # at the given host and port for changes in its Quad Store.
# #
# # 3. The virtuoso quad logger uses the isql interactive interface to store incremental
# # change files as rdf-patch.[1]
# #
# # 4. The virtuoso quad logger enables the propagation of the changes through the
# # Resource Sync Framework. See http://www.openarchives.org/rs/1.0/resourcesync
# #
# #
# # [1]To control the size of the files that record incremental changes it is best to set the
# # AutoCheckpointLogSize under Parameters in the virtuoso.ini file to a reasonable value.
#
#
# ###############################################################################
# # Set variables to reflect current conditions. Uncomment where needed.
# #
# ################################################# Docker run parameters #######
# #
# # The directory used for serving Resource Sync files.
DATA_DIR="$PWD/data"
# #
# # The name for the docker container
CONTAINER_NAME=quad_logger
# #
# # Docker User defined networks.
# # See: https://docs.docker.com/engine/userguide/networking/work-with-networks/#linking-containers-in-user-defined-networks
# # If you want to run the virtuoso quad logger within a user defined network, leave next two parameters uncommented.
USER_DEFINED_NETWORK=isolated_nw
USER_DEFINED_IP=172.25.3.5
# # If you want to run the virtuoso quad logger in a traditional network, comment out previous two parameters.
# #
# ####################################### virtuoso quad logger parameters #######
# #
# # At what host and port can the isql interface of the Virtuoso server be reached?
# # - If the Virtuoso server and the quad logger both are run under a user defined network specify the name, the alias or
# #   the id of the virtuoso server as host name.
# # - If the Virtuoso server runs as a (semi) public service specify the IP address or host name.
VIRTUOSO_SERVER_HOST_NAME=virtuoso_server
VIRTUOSO_SERVER_ISQL_PORT=1111
# #
# # The Virtuoso user. Default value is 'dba'.
VIRTUOSO_USER=dba
# #
# # The Virtuoso password.
read -sp "Virtuoso password for the user '$VIRTUOSO_USER' " VIRTUOSO_PASSWORD
VIRTUOSO_PASSWORD=${VIRTUOSO_PASSWORD:-dba}
echo
# #
# # The time between consecutive runs of the quad logger.
# # Value can be NUMBER[SUFFIX], where SUFFIX is
# #    s for seconds (the default)
# #    m for minutes.
# #    h for hours.
# #    d for days.
# # Default value is 3600 (1 hour).
#RUN_INTERVAL=20
# #
# # The location of transaction logs on the Virtuoso server.
# # Default value is '/usr/local/var/lib/virtuoso/db'.
#LOG_FILE_LOCATION=/usr/local/var/lib/virtuoso/db
# #
# # Should we insert stored procedures on the Virtuoso server automatically.
# # The procedures that will be inserted all start with 'vql_'.
# # Inserted procedures can be found with
# #   SQL> SELECT P_NAME FROM SYS_PROCEDURES WHERE P_NAME LIKE 'DB.DBA.vql_*';
# # If necessary they can be removed individually with
# #   SQL> DROP PROCEDURE {P_NAME};
# # Possible values: y|n. Default value is 'y'.
#INSERT_PROCEDURES=y
# #
# ## Dumps ####################################################################
# #
# # Should we dump the current state of the quad store.
# # Possible values: y|n
# # In case 'y' and no dump has been executed previously:
# # - Empty or remove the directory {DATA_DIR},
# #   especially, before dump starts {DATA_DIR} should not contain old patch files ('rdfpatch-*')
# #   and should not contain old dump files ('rdfdump-*');
# # - No transactions should take place during dump.
# # If a dump has been executed and was completed successfully, this parameter has no effect.
# # Default value is 'y'.
#DUMP_INITIAL_STATE=y
# #
# # Maximum amount of quads per dump file.
# # A value of 1000000 (1 milj. quads) will result in dump files with a size of approximately 150MB.
# # Default is 100000.
#MAX_QUADS_IN_DUMP_FILE=10000000
# #
# # Space-separated list of graph iris that are excluded from the dump.
# # As per default the following graphs are excluded from the dump:
# #   http://www.openlinksw.com/schemas/virtrdf#
# #   http://www.w3.org/ns/ldp#
# #   http://www.w3.org/2002/07/owl#
# #   http://localhost:8890/sparql
# #   http://localhost:8890/DAV/
#EXCLUDED_GRAPHS="http://www.openlinksw.com/schemas/virtrdf# \
#http://www.w3.org/ns/ldp# \
#http://www.w3.org/2002/07/owl# \
#http://localhost:8890/sparql \
#http://localhost:8890/DAV/ \
#http://other.excluded/graph \
#http://yet.another/excluded/graph#"
# #
# # Should we dump the current state of the quad store and then exit.
# # Possible values: y|n. Default value is 'n'.
#DUMP_AND_EXIT=n
# #
# ## Resource Sync ############################################################
# #
# # The base URL for publishing  resources in the Resource Sync Framework.
# # Default is 'http://example.org/'
#HTTP_SERVER_URL=http://foo.bar.com/rs/data
# #
# ###############################################################################

if [ -z $USER_DEFINED_NETWORK -o -z $USER_DEFINED_IP ]; then

    echo -e "\n-- Starting virtuoso quad logger"
    docker run -it --rm \
        -v $DATA_DIR:/datadir \
        --name "$CONTAINER_NAME" \
        -e="VIRTUOSO_SERVER_HOST_NAME=$VIRTUOSO_SERVER_HOST_NAME" \
        -e="VIRTUOSO_SERVER_ISQL_PORT=$VIRTUOSO_SERVER_ISQL_PORT" \
        -e="VIRTUOSO_USER=$VIRTUOSO_USER" \
        -e="VIRTUOSO_PASSWORD=$VIRTUOSO_PASSWORD" \
        -e="RUN_INTERVAL=$RUN_INTERVAL" \
        -e="LOG_FILE_LOCATION=$LOG_FILE_LOCATION" \
        -e="INSERT_PROCEDURES=$INSERT_PROCEDURES" \
        -e="DUMP_INITIAL_STATE=$DUMP_INITIAL_STATE" \
        -e="MAX_QUADS_IN_DUMP_FILE=$MAX_QUADS_IN_DUMP_FILE" \
        -e="EXCLUDED_GRAPHS=$EXCLUDED_GRAPHS" \
        -e="DUMP_AND_EXIT=$DUMP_AND_EXIT" \
        -e="HTTP_SERVER_URL=$HTTP_SERVER_URL" \
        bhenk/virtuoso-quad-log

else

    echo -e "\n-- Starting virtuoso quad logger under network '$USER_DEFINED_NETWORK'"
    docker run -it --rm \
        -v $DATA_DIR:/datadir \
        --net="$USER_DEFINED_NETWORK" --ip="$USER_DEFINED_IP" \
        --name "$CONTAINER_NAME" \
        -e="VIRTUOSO_SERVER_HOST_NAME=$VIRTUOSO_SERVER_HOST_NAME" \
        -e="VIRTUOSO_SERVER_ISQL_PORT=$VIRTUOSO_SERVER_ISQL_PORT" \
        -e="VIRTUOSO_USER=$VIRTUOSO_USER" \
        -e="VIRTUOSO_PASSWORD=$VIRTUOSO_PASSWORD" \
        -e="RUN_INTERVAL=$RUN_INTERVAL" \
        -e="LOG_FILE_LOCATION=$LOG_FILE_LOCATION" \
        -e="INSERT_PROCEDURES=$INSERT_PROCEDURES" \
        -e="DUMP_INITIAL_STATE=$DUMP_INITIAL_STATE" \
        -e="MAX_QUADS_IN_DUMP_FILE=$MAX_QUADS_IN_DUMP_FILE" \
        -e="EXCLUDED_GRAPHS=$EXCLUDED_GRAPHS" \
        -e="DUMP_AND_EXIT=$DUMP_AND_EXIT" \
        -e="HTTP_SERVER_URL=$HTTP_SERVER_URL" \
        bhenk/virtuoso-quad-log

fi
