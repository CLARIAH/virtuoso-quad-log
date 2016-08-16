#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import re, os
from abc import ABCMeta, abstractmethod
from glob import glob
from resync.utils import compute_md5_for_file
from resync.resource import Resource
from resync.resource_list import ResourceList


RS_WELL_KNOWN = ".well-known"
RS_RESOURCESYNC = "resourcesync"
RS_CAPABILITY_LIST_XML = "capability-list.xml"
RS_RESOURCE_DUMP_XML = "resource-dump.xml"

PATTERN_PATCH = "rdfpatch-"
PATTERN_DUMP = PATTERN_PATCH + "0d"

PREFIX_COMPLETED_PART = "part_def_"
PREFIX_END_PART = "part_end_"
PREFIX_MANIFEST = "manifest_"


class Synchronizer:
    """
    Abstract base class for publishing resources in accordance with the Resourcesync Framework.
    A Synchronizer is responsible for publishing metadata up to capability-list.xml.
    See: http://www.openarchives.org/rs/1.0/resourcesync
    """
    __metaclass__ = ABCMeta

    def __init__(self, resource_dir, publish_dir, publish_url,
                 src_desc_url=None,
                 max_files_compressed=50000,
                 write_separate_manifest=True,
                 move_resources=False):
        """
        Initialize a new Synchronizer.
        :param resource_dir: the source directory for resources
        :param publish_dir: the directory resources should be published to
        :param publish_url: public url pointing to publish dir
        :param src_desc_url: public url pointing to resource description
        :param max_files_compressed: the maximum number of resource files that should be compressed in one zip file
        :param write_separate_manifest: will each zip file be accompanied by a separate resourcedump manifest.
        :param move_resources: Do we move the zipped resources to publish_dir or simply delete them from resource_dir.
        :return:
        """
        self.resource_dir = resource_dir
        self.publish_dir = publish_dir

        self.publish_url = publish_url
        if self.publish_url is None or self.publish_url == "":
            self.publish_url = "http://example.com/"
        if self.publish_url[-1] != '/':
            self.publish_url += '/'

        self.src_desc_url = src_desc_url
        if self.src_desc_url is None:
            self.src_desc_url = self.publish_url + RS_WELL_KNOWN + "/" + RS_RESOURCESYNC

        if max_files_compressed > 50000:
            raise RuntimeError(
                "%s exceeds limit of 50000 items per document of the Sitemap protocol." % str(max_files_compressed))
        self.max_files_compressed = max_files_compressed

        self.write_separate_manifest = write_separate_manifest
        self.move_resources = move_resources

        self.dump_timestamp = None


    @staticmethod
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

    @staticmethod
    def is_same(rl_1, rl_2):
        """
        Compare (uri's of resources of) two resourcelists for equality.
        :param rl_1: a Resourcelist
        :param rl_2: a Resourcelist
        :return: True if rl_1 resources are equal to rl_2 resources, False otherwise
        """
        same, updated, deleted, created = rl_1.compare(rl_2)
        return len(same) == len(rl_1) == len(rl_2)

    @staticmethod
    def last_modified(resourcelist):
        """
        Find the last modified date of resources in resourcelist.
        :param resourcelist: the resourcelist to be inspected
        :return: last modified date of resource last modified
                    or None if last modified date not specified or empty resourcelist
        """
        lastmod = None
        for resource in resourcelist:
            rlm = resource.lastmod
            if rlm > lastmod:
                lastmod = rlm

        return lastmod

    def extract_timestamp(self, path):
        """
        Extract the timestamp from a file denoted with path. The filename should start with 'rdfpatch-'.
        :param path: path to the file
        :return: timestamp extracted from filename or file contents
        """
        filename = os.path.basename(path)
        if filename.startswith(PATTERN_DUMP):
            # All timestamps of dump files are the same, so keep it in a variable once set.
            if self.dump_timestamp is None:
                t = None
                with open(path) as search:
                    for line in search:
                        if re.match("# at checkpoint.*", line):
                            t = re.findall('\d+', line)[0]
                            break

                if t is None:
                    raise RuntimeError(
                        "Found dump files but did not find timestamp for checkpoint in '%s'" % path)

                self.dump_timestamp = self.compute_timestamp(t)

            timestamp = self.dump_timestamp

        elif filename.startswith(PATTERN_PATCH):
            _, raw_ts = filename.split("-")
            timestamp = self.compute_timestamp(raw_ts)

        else:
            raise RuntimeError("Unable to extract timestamp: $s does not start with %s" % (filename, PATTERN_PATCH))

        return timestamp

    def list_resources_chunk(self):
        """
        Fill a resource list up to max_files_compressed or with as much rdf-files as there are left in resource_dir.
        A boolean indicates whether the resource_dir was exhausted.
        :return: the ResourceList, exhausted
        """
        resourcelist = ResourceList()
        exhausted = self.list_patch_files(resourcelist, max_files=self.max_files_compressed)
        return resourcelist, exhausted

    def list_patch_files(self, resourcelist, max_files=-1):
        """
        Append resources with the name pattern 'rdfpatch-*' to a resourcelist. All resources in
        resource_dir are included except for the last one in alphabetical sort order. If max_files is set to a
        value greater than 0, will only include up to max_files.
        :param resourcelist: the resourcelist to append to
        :param max_files: the maximum nimber of resources to append to the list
        :return: True if the list includes the one but last rdfpatch-* file in resource_dir, False otherwise
        """
        patchfiles = sorted(glob(os.path.join(self.resource_dir, PATTERN_PATCH + "*")))
        if len(patchfiles) > 0:
            patchfiles.pop()  # remove last from list
        n = 0
        for file in patchfiles:
            filename = os.path.basename(file)
            timestamp = self.extract_timestamp(file)
            length = os.stat(file).st_size
            md5 = compute_md5_for_file(file)
            resourcelist.add(
                Resource(self.publish_url + filename, md5=md5, length=length, lastmod=timestamp, path=file))
            n += 1
            if 0 < max_files == n:
                break

        exhausted = len(patchfiles) == n
        return exhausted

    @abstractmethod
    def publish(self):
        """
        Publish the resources found in source_dir in accordance with the Resourcesync Framework in sink_dir.
        """
        pass
