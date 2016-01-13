#!/usr/local/bin/python

from resync.resource_list import ResourceList
from resync.capability_list import CapabilityList
from resync.source_description import SourceDescription

from resync.resource import Resource
from argparse import ArgumentParser

from os import listdir
from os.path import isfile, isdir, join

parser = ArgumentParser()

# argparse arguments:
# --resource-dir: containing files to be synced
# --resource-url: public url pointing to resource dir
parser.add_argument('--resource-url', required=True)
parser.add_argument('--resource-dir', required=True)
args = parser.parse_args()

if not isdir(args.resource_dir):
	raise IOError(args.resource_dir + " is not a directory")

rl = ResourceList()
timestamps = []
for filename in listdir(args.resource_dir):
	_, raw_ts = filename.split("-")
	ts = (
		raw_ts[:4] + "-" + 
		raw_ts[4:6] + "-" + 
		raw_ts[6:8] + "T" + 
		raw_ts[8:10] + ":" + 
		raw_ts[10:12] + ":" +
		raw_ts[12:14] + "Z"
	)
	timestamps.append(ts)
	rl.add(Resource(args.resource_url + "/" + filename, lastmod=ts))

# Print to file at args.resource_dir + "/resource-list.xml"
resource_list_file = open(args.resource_dir + "/resource-list.xml", "w")
resource_list_file.write(rl.as_xml())
resource_list_file.close()
print "Wrote resource list to: " + args.resource_dir + "/resource-list.xml"

timestamps.sort()

caps = CapabilityList()
caps.add_capability(rl, args.resource_url + "/resource-list.xml")
if len(timestamps) > 0:
	caps.md['from'] = timestamps[0]

# Print to file at args.resource_dir + "/capability-list.xml"
capability_list_file = open(args.resource_dir + "/capability-list.xml", "w")
capability_list_file.write(caps.as_xml())
capability_list_file.close()

print "Wrote capability list to: " + args.resource_dir + "/capability-list.xml"

rsd = SourceDescription()
rsd.md_at = None
rsd.add_capability_list(args.resource_url + "/capability-list.xml")

# Print to file at args.resource_dir + "/resourcesync"
source_description_file = open(args.resource_dir + "/resourcesync", "w")
source_description_file.write(rsd.as_xml())
source_description_file.close()

print "Wrote source description to: " + args.resource_dir + "/resourcesync"
