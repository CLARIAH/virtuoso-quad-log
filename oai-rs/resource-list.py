#!/usr/local/bin/python

from resync.resource_list import ResourceList
from resync.capability_list import CapabilityList
from resync.source_description import SourceDescription

from resync.resource import Resource
from argparse import ArgumentParser

from os import listdir
from os.path import isfile, isdir, join

parser = ArgumentParser()

# TODO: which arguments? 
# - dir A containing files to be synced (now called --resource-dir)
# - public url A pointing to dir A (now called --resource-url)
# - dir B to write these oai-rs files to...
# - public url B to access these oai-rs files from (used in refs in capability list and source description)...
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
	rl.add(Resource(args.resource_url + filename, lastmod=ts))

# TODO: print to file at given location
print rl.as_xml()

timestamps.sort()

# TODO: create capability list from ResourceList rl (see: https://github.com/resync/resync/blob/master/resync/test/test_capability_list.py)
caps = CapabilityList()
caps.add_capability( rl, "http://WHEREDOIPOINTTHISQUESTIONMARK/resource-list.xml")
caps.md['from'] = timestamps[0]

# TODO: print to file at given location
# print caps.as_xml()

# TODO: create source description (see: https://github.com/resync/resync/blob/master/resync/test/test_source_description.py)
rsd = SourceDescription()
rsd.describedby = "http://YETANOTHERURLIDONOTKNOWWHERETOPUT"
rsd.md_at = None
rsd.add_capability_list("http://WHEREDOIPOINTTHISQUESTIONMARK/capability-list.xml")

# TODO: print to file at given location
# print rsd.as_xml()