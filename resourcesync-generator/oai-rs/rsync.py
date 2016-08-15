#! /usr/bin/env python2
# -*- coding: utf-8 -*-

from argparse import ArgumentParser
from syncdirector import SyncDirector

# Publish rdf patch files as resource dumps.

parser = ArgumentParser()
# parser arguments:
# --resource_dir: directory containing files to be synced
# --publish_dir: directory where files will be published
# --publish_url: public url pointing to publish dir
# --synchronizer_class: class to handle the publishing of resources
# --max_files_compressed: the maximum number of resource files that should be compressed in one file
# --write_separate_manifest: 'True' to write manifest included in published zips also in publish_dir, 'False' otherwise
# --move_resources: Completed zips contain max_files_in_zip resources. Resource handling of completed zips.
#                   'True' to move resources from resource_dir to publish_dir,
#                   'False' to simply remove them from resource_dir.
parser.add_argument('--resource_dir', required=True)
parser.add_argument('--publish_dir', required=True)
parser.add_argument('--publish_url', required=True)
parser.add_argument('--synchronizer_class', default="zipsynchronizer.ZipSynchronizer")
parser.add_argument('--max_files_compressed', type=int, default=50000)
parser.add_argument('--write_separate_manifest', default="y")
parser.add_argument('--move_resources', default="n")
args = parser.parse_args()

write_separate_manifest = args.write_separate_manifest == "y"
move_resources = args.move_resources == "y"

syncer = SyncDirector(args.resource_dir, args.publish_dir, args.publish_url, args.synchronizer_class,
                         args.max_files_compressed, write_separate_manifest, move_resources)
syncer.synchronize()