#!/usr/bin/env bash
#
# PLAY_UDN
#
# Virtuoso Quad Store <== virtuoso-quad-logger -> [patch data] <- RS-source -> [rs-list] <== RS-destination -> [sync data]
#                                                                                            |
#                                                 [patch data] <== ...........................
#
# === Legend ======================
# [....]    = data on drive
#   <== ..  = network communication
#    <-     = file handling
#   text    = process
#
# Run above pictured chain under a Docker user defined network (udn).
#
#
MACHINE_NAME=play-udn
#
# Start a Docker daemon or connect if started.
if $(docker-machine ls | grep '$MACHINE_NAME') ; then
    echo "$MACHINE_NAME running, connecting to it..."

else
    echo "$MACHINE_NAME not running, creating it..."
    docker-machine create "$MACHINE_NAME"
    docker-machine create --driver virtualbox "$MACHINE_NAME"
fi
