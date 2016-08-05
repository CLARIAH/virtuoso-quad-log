#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import os, synchronizer
from synchronizer import Synchronizer
from argparse import ArgumentParser
from resync.resource_dump import ResourceDump
from resync.sitemap import Sitemap
from glob import glob

# Alternative strategy to publish rdf patch files as resource dumps.

parser = ArgumentParser()
# argparse arguments:
# --resource_dir: directory containing files to be synced
# --publish_dir: directory where files will be published
# --publish_url: public url pointing to publish dir
# --max_files_in_zip: the maximum number of resource files that should be compressed in one zip file
# --write_separate_manifest: 'True' to write manifest included in published zips also in publish_dir, 'False' otherwise
# --move_resources: Completed zips contain max_files_in_zip resources. Resource handling of completed zips.
#                   'True' to move resources from resource_dir to publish_dir,
#                   'False' to simply remove them from resource_dir.
parser.add_argument('--resource_dir', required=True)
parser.add_argument('--publish_dir', required=True)
parser.add_argument('--publish_url', required=True)
parser.add_argument('--max_files_in_zip', type=int, default=50000)
parser.add_argument('--write_separate_manifest', default="y")
parser.add_argument('--move_resources', default="n")
args = parser.parse_args()

syncer = Synchronizer(args.resource_dir, args.publish_dir, args.publish_url,
                    args.max_files_in_zip, args.write_separate_manifest == "y", args.move_resources == "y")
syncer.publish()