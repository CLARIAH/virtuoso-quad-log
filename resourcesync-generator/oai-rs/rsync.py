#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import sys
# Enable dynamic imports
sys.path.append(".")

from argparse import ArgumentParser
from syncdirector import SyncDirector

# Publish rdf patch files as resource dumps.

# Bundle up to max_files_compressed rdf patch files as successive definitely published resources;
# bundle the remainder of rdf patch files as temporary bundled resources.

parser = ArgumentParser()
# parser arguments:
# --source_dir: directory containing files to be synced
# --sink_dir: directory where files will be published
# --publish_url: public url pointing to sink dir
# --builder_class: class to handle the publishing of resources
# --max_files_compressed: the maximum number of resource files that should be compressed in one file
# --write_separate_manifest: 'y' to write manifest included in published dump also in sink_dir as a separate file
# --move_resources: 'y' to move definitely published resources from source_dir to sink_dir,
#                   otherwise simply remove them from resource_dir.
parser.add_argument('--source_dir', required=True)
parser.add_argument('--sink_dir', required=True)
parser.add_argument('--publish_url', required=True)
parser.add_argument('--builder_class', default="zipsynchronizer.ZipSynchronizer")
parser.add_argument('--max_files_compressed', type=int, default=50000)
parser.add_argument('--write_separate_manifest', default="y")
parser.add_argument('--move_resources', default="n")
args = parser.parse_args()

write_separate_manifest = args.write_separate_manifest == "y"
move_resources = args.move_resources == "y"

director = SyncDirector(args.source_dir, args.sink_dir, args.publish_url, args.builder_class,
                        args.max_files_compressed, write_separate_manifest, move_resources)
director.synchronize()