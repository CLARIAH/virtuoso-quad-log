#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import importlib, sys, os, shutil, re
from abc import ABCMeta, abstractmethod
from resync.source_description import SourceDescription
from resync.sitemap import Sitemap
# Enable dynamic imports
sys.path.append(".")

FILE_HANDSHAKE = "started_at.txt"
FILE_INDEX = "index.csv"

DUMP_PATTERN = "rdfpatch-0d"

class Synchronizer:
    """

    """
    __metaclass__ = ABCMeta

    def __init__(self, resource_dir, publish_dir, publish_url, src_desc_url,
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
        filename = os.path.basename(path)
        if filename.startswith(DUMP_PATTERN):
            if self.dump_timestamp is None:
                with open(path) as search:
                    for line in search:
                        if re.match("# at checkpoint.*", line):
                            t = re.findall('\d+', line)[0]
                            break

                if t is None:
                    raise RuntimeError(
                        "Found dump files but did not find timestamp for checkpoint in '%s'" % dumpfiles[0])

                self.dump_timestamp = self.compute_timestamp(t)

            timestamp = self.dump_timestamp
        else:
            _, raw_ts = filename.split("-")
            timestamp = self.compute_timestamp(raw_ts)

        return timestamp

    @abstractmethod
    def publish(self):
        """
        compress the resources found in resource_dir.
        :return:
        """
        pass


class SyncDirector(object):
    """
    from http://www.openarchives.org/rs/1.0/resourcesync#SourceDesc
        A Source Description is a mandatory document that enumerates the Capability Lists offered by a Source.
        Since a Source has one Capability List per set of resources that it distinguishes, the Source Description
        will enumerate as many Capability Lists as the Source has distinct sets of resources.

    """

    def __init__(self, source_dir, publish_dir, publish_url, synchronizer_class,
                 max_files_compressed=50000, write_separate_manifest=True,
                 move_resources=False):
        """
        Initialize a new SyncDirector.
        :param source_dir: the source directory for resources
        :param publish_dir: the directory resources should be published to
        :param publish_url: public url pointing to publish dir
        :param synchronizer_class: class to handle the publishing of resources
        :param max_files_compressed: the maximum number of resource files that should be compressed in one zip file
        :param write_separate_manifest: will each zip file be accompanied by a separate resourcedump manifest.
        :param move_resources: Do we move the zipped resources to publish_dir or simply delete them from resource_dir.
        :return:
        """
        self.source_dir = source_dir
        self.publish_dir = publish_dir
        self.publish_url = publish_url
        if self.publish_url is None or self.publish_url == "":
            self.publish_url = "http://example.com/"
        if self.publish_url[-1] != '/':
            self.publish_url += '/'
        if max_files_compressed > 50000:
            raise RuntimeError(
                "%s exceeds limit of 50000 items per document of the Sitemap protocol." % str(max_files_compressed))
        self.max_files_compressed = max_files_compressed
        self.write_separate_manifest = write_separate_manifest
        self.move_resources = move_resources

        names = synchronizer_class.rsplit(".", 1)
        self.sync_class = getattr(importlib.import_module(names[0]), names[1])

        self.handshake = None

        self.src_desc_url = self.publish_url + ".well-known/resourcesync"
        self.src_desc_path = os.path.join(self.publish_dir, ".well-known", "resourcesync")


    def synchronize(self):
        """

        :return:
        """
        if not os.path.isdir(self.source_dir):
            os.makedirs(self.source_dir)
            print "Created %s" % self.source_dir

        if not os.path.isdir(self.publish_dir):
            os.makedirs(self.publish_dir)
            print "Created %s" % self.publish_dir

        self.handshake = self.verify_handshake()
        if self.handshake is None:
            return
        ####################

        print "Synchronizing state as of %s" % self.handshake

        ### initial resource description
        wellknown = os.path.join(self.publish_dir, ".well-known")
        if not os.path.isdir(wellknown):
            os.makedirs(wellknown)

        src_desc = SourceDescription()
        new_src_desc = True
        # Load existing resource-description, if any.
        if os.path.isfile(self.src_desc_path):
            new_src_desc = False
            with open(self.src_desc_path, "r") as src_desc_file:
                sm = Sitemap()
                sm.parse_xml(src_desc_file, resources=src_desc)

        count_lists = len(src_desc.resources)

        ### resources in subdirectories or main directory
        index_file = os.path.join(self.source_dir, FILE_INDEX)
        if os.path.isfile(index_file):
            self.synchronize_subdirs(src_desc)
        else:
            self.execute_sync(self.source_dir, self.publish_dir, self.publish_url, src_desc)

        if new_src_desc or count_lists != len(src_desc.resources):
            ### publish resource description
            with open(self.src_desc_path, "w") as src_desc_file:
                src_desc_file.write(src_desc.as_xml())
                print "Published new resource description. See %s" % self.src_desc_url

    def synchronize_subdirs(self, src_desc):

        for dirname in os.walk(self.source_dir).next()[1]:
            source = os.path.join(self.source_dir, dirname)
            sink = os.path.join(self.publish_dir, dirname)
            publish_url = self.publish_url + dirname + "/"
            self.execute_sync(source, sink, publish_url, src_desc)

    def execute_sync(self, source, sink, url, src_desc):

        synchronizer = self.sync_class(source, sink, url,
                            self.src_desc_url, self.max_files_compressed,
                            self.write_separate_manifest, self.move_resources)
        synchronizer.publish()
        capa_list_url = url + "capability-list.xml"
        if not capa_list_url in src_desc.resources:
            src_desc.add_capability_list(capa_list_url)

    def verify_handshake(self):
        """
        Resources in resource_dir and publish_dir should stem from the same start date.
        This method compares start date of resource_dir with start_date of publish_dir.
        If they are not the same adeqate action will be taken.
        :return: the current value of the handshake or None if no handshake was found.
        """
        resource_handshake = None
        publish_handshake = None

        path_resource_handshake = os.path.join(self.source_dir, FILE_HANDSHAKE)
        if os.path.isfile(path_resource_handshake):
            with open(path_resource_handshake, "r") as r_file:
                resource_handshake = r_file.read()

        path_publish_handshake = os.path.join(self.publish_dir, FILE_HANDSHAKE)
        if os.path.isfile(path_publish_handshake):
            with open(path_publish_handshake, "r") as r_file:
                publish_handshake = r_file.read()

        if resource_handshake is None:
            print "Error: No resource_handshake found. Not interfering with status quo of published resources."
            return None

        if publish_handshake is None:
            # This can only be at the very start of synchronizing with a fresh empty publish_dir
            if self.walk_publish_dir() > 0:
                print "Error: No publish_handshake found and %s not empty. " \
                      "Not interfering with status quo of published resources." % self.publish_dir
                return None

        if resource_handshake != publish_handshake:
            print "Resource_handshake is %s, publish_handshake is % s. Shrubbing %s" \
                  % (resource_handshake, publish_handshake, self.publish_dir)
            self.walk_publish_dir(remove_our_files=True)
            publish_handshake = None

        if resource_handshake and publish_handshake is None:
            with open(path_publish_handshake, "w") as w_file:
                w_file.write(resource_handshake)
            print "Signed new handshake: %s" % resource_handshake

        return resource_handshake

    def walk_publish_dir(self, remove_our_files=False):
        our_things = 0
        for a_file in os.listdir(self.publish_dir):
            if self.is_our_file(a_file):
                our_things += 1
                if remove_our_files:
                    file_path = os.path.join(self.publish_dir, a_file)
                    if os.path.isfile(file_path):
                        os.remove(file_path)
                    elif os.path.isdir(file_path):
                        shutil.rmtree(file_path)
        return our_things

    def is_our_file(self, a_file):
        return a_file.startswith((FILE_HANDSHAKE,
                                  FILE_INDEX,
                                  "resource-dump.xml",
                                  "capability-list.xml",
                                  "manifest_",
                                  "part_",
                                  "zip_end")) \
               or os.path.isdir(os.path.join(self.publish_dir, a_file))