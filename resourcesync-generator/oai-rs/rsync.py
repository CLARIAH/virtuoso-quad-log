#! /usr/bin/env python2
# -*- coding: utf-8 -*-

from argparse import ArgumentParser
from synchronizer import Synchronizer

# Alternative strategy to publish rdf patch files as resource dumps. Not implemented.

parser = ArgumentParser()
# argparse arguments:
# --resource_dir: containing files to be synced
# --publish_dir: directory where files will be published
# --publish_url: public url pointing to publish dir
# --max_files_in_zip: the maximum number of resource files that should be compressed in one zip file
parser.add_argument('--resource_dir', required=True)
parser.add_argument('--publish_dir', required=True)
parser.add_argument('--publish_url', required=True)
parser.add_argument('--max_files_in_zip', default=50000)
args = parser.parse_args()

synchronizer = Synchronizer(args.resource_dir, args.publish_dir, args.publish_url, args.max_files_in_zip)
synchronizer.publish()