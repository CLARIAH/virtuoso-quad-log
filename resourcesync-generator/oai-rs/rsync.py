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
parser.add_argument('--write_separate_manifest', type=bool, default=True)
parser.add_argument('--move_resources', type=bool, default=False)
args = parser.parse_args()

syncer = Synchronizer(args.resource_dir, args.publish_dir, args.publish_url,
                            args.max_files_in_zip, args.write_separate_manifest, args.move_resources)
try:
    syncer.publish()

except:
    # Something went wrong. Best we can do is clean up end of zip chain.
    zip_end_files = glob(os.path.join(args.publish_dir, synchronizer.PREFIX_END_ZIP + "*.zip"))
    for ze_file in zip_end_files:
        os.remove(ze_file)
        print "error recovery: removed %s" % ze_file

    zip_end_xmls = glob(os.path.join(args.publish_dir, synchronizer.PREFIX_END_ZIP + "*.xml"))
    for ze_xml in zip_end_xmls:
        os.remove(ze_xml)
        print "error recovery: removed %s" % ze_xml

    zip_end_manis = glob(os.path.join(args.publish_dir, synchronizer.PREFIX_MANIFEST + synchronizer.PREFIX_END_ZIP + "*.xml"))
    for ze_mani in zip_end_manis:
        os.remove(ze_mani)
        print "error recovery: removed %s" % ze_mani

    # remove zip-end entries from resource-dump.xml
    rs_dump_path = os.path.join(args.publish_dir, "resource-dump.xml")
    rs_dump = ResourceDump()
    if os.path.isfile(rs_dump_path):
        with open(rs_dump_path, "r") as rs_dump_file:
            sm = Sitemap()
            sm.parse_xml(rs_dump_file, resources=rs_dump)

    if args.publish_url[-1] != '/':
        args.publish_url += '/'
    prefix = args.publish_url + synchronizer.PREFIX_END_ZIP

    for uri in rs_dump.resources.keys():
        if uri.startswith(prefix):
            del rs_dump.resources[uri]
            print "error recovery: removed %s from %s" % (uri, rs_dump_path)

    with open(rs_dump_path, "w") as rs_dump_file:
        rs_dump_file.write(rs_dump.as_xml())

    print "error recovery: walk through error recovery completed. Now raising ..."
    raise
