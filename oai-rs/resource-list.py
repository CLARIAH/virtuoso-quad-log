#!/usr/local/bin/python

from resync.resource_list import ResourceList
from resync.resource import Resource
from argparse import ArgumentParser

from os import listdir
from os.path import isfile, isdir, join

parser = ArgumentParser()
parser.add_argument('--resource-url', required=True)
parser.add_argument('--resource-dir', required=True)
args = parser.parse_args()

if not isdir(args.resource_dir):
	raise IOError(args.resource_dir + " is not a directory")

rl = ResourceList()
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
	rl.add(Resource(args.resource_url + filename, lastmod=ts))

# TODO: print to file at given location
print rl.as_xml()


# TODO: create capability list from ResourceList rl (see: https://github.com/resync/resync/blob/master/resync/test/test_capability_list.py)


# TODO: create source description