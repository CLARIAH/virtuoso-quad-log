#!/bin/bash --

# Start a Docker container with the virtuoso quad logger.
# 
# The virtuosos quad logger will poll the transaction logs of the Virtuoso instance 
# at the given host and port for changes in its Quad Store. The virtuosos quad logger
# uses the isql interactive interface and to do so.
# 

###############################################################################
# Set variables to reflect current conditions
#
# The directory used for serving Resource Sync files:
DATA_DIR="$PWD/data"
#
# The Virtuoso host name:
VIRTUOSO_ISQL_ADDRESS=192.168.99.100
#
# The Virtuoso isql port:
VIRTUOSO_ISQL_PORT=1111
#
#The Virtuoso user:
VIRTUOSO_USER=dba
#
#The Virtuoso password:
read -sp "Virtuoso password for the user '$VIRTUOSO_USER' " VIRTUOSO_PASSWORD
VIRTUOSO_PASSWORD=${VIRTUOSO_PASSWORD:-dba}
echo
#
# The time between consecutive runs of the quad logger.
# Default unit is seconds:
RUN_INTERVAL=60
#
# The location for transaction logs on the Virtuoso server:
LOG_FILE_LOCATION=/usr/local/var/lib/virtuoso/db
###############################################################################

mkdir -p "$DATA_DIR"

# Check if the Virtuoso server can be reached
echo -e "\n-- Testing connection to $VIRTUOSO_ISQL_ADDRESS:$VIRTUOSO_ISQL_PORT"
connected=$(nc -vz "$VIRTUOSO_ISQL_ADDRESS" "$VIRTUOSO_ISQL_PORT")
if [ "$?" != 0 ]; then
	exit 1
fi

echo -e "\n-- Starting virtuoso quad logger"
docker run -it --rm -v $DATA_DIR:/datadir \
	--name vql \
    -e="VIRTUOSO_ISQL_ADDRESS=$VIRTUOSO_ISQL_ADDRESS" \
    -e="VIRTUOSO_ISQL_PORT=$VIRTUOSO_ISQL_PORT" \
    -e="VIRTUOSO_USER=$VIRTUOSO_USER" \
    -e="VIRTUOSO_PASSWORD=$VIRTUOSO_PASSWORD" \
    -e="RUN_INTERVAL=$RUN_INTERVAL" \
    -e="LOG_FILE_LOCATION=$LOG_FILE_LOCATION" \
    virtuoso-quad-log:1.0.0