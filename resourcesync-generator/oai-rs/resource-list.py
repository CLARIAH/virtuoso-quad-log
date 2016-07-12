#!/usr/bin/env python

from resync.resource_list import ResourceList
from resync.capability_list import CapabilityList
from resync.source_description import SourceDescription
from resync.utils import compute_md5_for_file

from resync.resource import Resource
from argparse import ArgumentParser

from os import listdir, stat, makedirs
from os.path import isfile, isdir, join, basename

from glob import glob
import re

parser = ArgumentParser()

# argparse arguments:
# --resource-dir: containing files to be synced
# --resource-url: public url pointing to resource dir
parser.add_argument('--resource-url', required=True)
parser.add_argument('--resource-dir', required=True)
args = parser.parse_args()

if args.resource_url[-1] != '/':
	args.resource_url += '/'

if not isdir(args.resource_dir):
	raise IOError(args.resource_dir + " is not a directory")

def compute_timestamp(raw_ts):
    """
    Convert a string like '20160613082341' into an xml-date format '2016-06-13T08:23:41Z'.
    :param raw_ts: a timestamp in a raw format
    :return: raw_ts as xml date format
    """
    ts = (
        raw_ts[:4] + "-" +
        raw_ts[4:6] + "-" +
        raw_ts[6:8] + "T" +
        raw_ts[8:10] + ":" +
        raw_ts[10:12] + ":" +
        raw_ts[12:14] + "Z"
    )
    return ts

rl = ResourceList()
timestamps = []

# Add dump files to the resource list. Last modified for all these files is the time dump was executed.
# Last modified is recorded in each file in a line starting with '# at checkpoint'.
t = None
dumpfiles = sorted(glob(args.resource_dir + "/rdfdump-*"))
if len(dumpfiles) > 0:
    lastfile = dumpfiles[len(dumpfiles) - 1]
    with open(lastfile) as search:
        for line in search:
            if re.match("# at checkpoint.*", line):
                t = re.findall('\d+', line)[0]

    if t is None:
        raise RuntimeError("Found dump files but did not find timestamp for checkpoint in '%s'" % lastfile)

    ts = compute_timestamp(t)
    timestamps.append(ts)
    for file in dumpfiles:
        filename = basename(file)
        length = stat(file).st_size
        md5 = compute_md5_for_file(file)
        rl.add(Resource(args.resource_url + filename, md5=md5, length=length, lastmod=ts))

# Add rdf-patch files to resourcelist. Last modified can be computed from the filename.
for filename in listdir(args.resource_dir):
	if filename[:len("rdfpatch-")] != "rdfpatch-":
		continue
	_, raw_ts = filename.split("-")
	ts = compute_timestamp(raw_ts)
	timestamps.append(ts)

	file = join(args.resource_dir, filename)
	length = stat(file).st_size
	md5 = compute_md5_for_file(file)
	rl.add(Resource(args.resource_url + filename, md5=md5, length=length, lastmod=ts))

# Print to file at args.resource_dir + "/resource-list.xml"
resource_list_file = open(args.resource_dir + "/resource-list.xml", "w")
resource_list_file.write(rl.as_xml())
resource_list_file.close()
#print "Wrote resource list to: " + args.resource_dir + "/resource-list.xml"

timestamps.sort()

caps = CapabilityList()
caps.add_capability(rl, args.resource_url + "resource-list.xml")
if len(timestamps) > 0:
	caps.md['from'] = timestamps[0]

# Print to file at args.resource_dir + "/capability-list.xml"
capability_list_file = open(args.resource_dir + "/capability-list.xml", "w")
capability_list_file.write(caps.as_xml())
capability_list_file.close()
#print "Wrote capability list to: " + args.resource_dir + "/capability-list.xml"

rsd = SourceDescription()
rsd.md_at = None
rsd.add_capability_list(args.resource_url + "capability-list.xml")

wellknown = args.resource_dir + "/.well-known"
if not isdir(wellknown):
    makedirs(wellknown)

# Print to file at args.resource_dir + "/resourcesync"
source_description_file = open(wellknown + "/resourcesync", "w")
source_description_file.write(rsd.as_xml())
source_description_file.close()
#print "Wrote source description to: " + args.resource_dir + "/resourcesync"

print "Published %s resources under Resource Sync Framework in %s" % (str(len(rl.resources)), args.resource_dir)
