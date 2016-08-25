#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import importlib
import os
import shutil

from resync.sitemap import Sitemap
from resync.source_description import SourceDescription
from synchronizer import RS_RESOURCESYNC, RS_WELL_KNOWN, RS_CAPABILITY_LIST_XML, RS_RESOURCE_DUMP_XML, \
    PREFIX_MANIFEST, PREFIX_END_PART, PREFIX_COMPLETED_PART, PATTERN_RDF_OUT

FILE_HANDSHAKE = "vql_started_at.txt"
FILE_INDEX = "vql_graph_folder.csv"
FILE_FILED_FILES = "vql_files_count.txt"
FILE_SYNCED_FILES = "vql_files_count.txt"


class SyncDirector(object):
    """
    Directs the publishing of resources in accordance with the Resourcesync Framework.
    A Syncdirector is responsible for publishing the source description as .well-known/resourcesync.
    See: http://www.openarchives.org/rs/1.0/resourcesync

    from http://www.openarchives.org/rs/1.0/resourcesync#SourceDesc
        A Source Description is a mandatory document that enumerates the Capability Lists offered by a Source.
        Since a Source has one Capability List per set of resources that it distinguishes, the Source Description
        will enumerate as many Capability Lists as the Source has distinct sets of resources.

    """

    def __init__(self, source_dir, sink_dir, publish_url, synchronizer_class,
                 max_files_compressed=50000, write_separate_manifest=True,
                 move_resources=False):
        """
        Initialize a new SyncDirector.
        :param source_dir: the source directory for resources
        :param sink_dir: the directory resources should be published to
        :param publish_url: public url pointing to publish dir
        :param synchronizer_class: class to handle the publishing of resources
        :param max_files_compressed: the maximum number of resource files that should be compressed in one zip file
        :param write_separate_manifest: will each zip file be accompanied by a separate resourcedump manifest.
        :param move_resources: Do we move the zipped resources to publish_dir or simply delete them from resource_dir.
        :return:
        """
        self.source_dir = source_dir
        self.sink_dir = sink_dir
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

        self.src_desc_url = self.publish_url + RS_WELL_KNOWN + "/" + RS_RESOURCESYNC
        self.src_desc_path = os.path.join(self.sink_dir, RS_WELL_KNOWN, RS_RESOURCESYNC)
        self.total_count_def_resources = 0
        self.total_diff_end_resources = 0

    def synchronize(self):
        """
        Publish the resources found in source_dir in accordance with the Resourcesync Framework in sink_dir.
        """
        if not os.path.isdir(self.source_dir):
            os.makedirs(self.source_dir)
            print "Created %s" % self.source_dir

        if not os.path.isdir(self.sink_dir):
            os.makedirs(self.sink_dir)
            print "Created %s" % self.sink_dir

        self.handshake = self.verify_handshake()
        if self.handshake is None:
            return
        ####################

        # print "Synchronizing state as of %s" % self.handshake

        ### initial resource description
        wellknown = os.path.join(self.sink_dir, RS_WELL_KNOWN)
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
        ### the existance of FILE_INDEX indicates whether resources reside directly in source_dir or in subdirectories.
        index_file = os.path.join(self.source_dir, FILE_INDEX)
        if os.path.isfile(index_file):
            for dirname in os.walk(self.source_dir).next()[1]:
                source = os.path.join(self.source_dir, dirname)
                sink = os.path.join(self.sink_dir, dirname)
                publish_url = self.publish_url + dirname + "/"
                self.__execute_sync__(source, sink, publish_url, src_desc)
        else:
            self.__execute_sync__(self.source_dir, self.sink_dir, self.publish_url, src_desc)

        if new_src_desc or count_lists != len(src_desc.resources):
            ### publish resource description
            with open(self.src_desc_path, "w") as src_desc_file:
                src_desc_file.write(src_desc.as_xml())
                print "New resource description. See %s" % self.src_desc_url

        self.report()

    def __execute_sync__(self, source, sink, url, src_desc):
        """
        Execute synchronisation of one source directory.
        :param source: the directory where resources reside
        :param sink: the directory to publish resources
        :param url: the public url pointing to the sink
        :param src_desc: the current SourceDescription
        """
        synchronizer = self.sync_class(source, sink, url,
                            self.src_desc_url, self.max_files_compressed,
                            self.write_separate_manifest, self.move_resources)
        state_changed, count_def_resources, diff_end_resources = synchronizer.publish()
        self.total_count_def_resources += count_def_resources
        self.total_diff_end_resources += diff_end_resources
        if state_changed:
            capa_list_url = url + RS_CAPABILITY_LIST_XML
            if not capa_list_url in src_desc.resources:
                src_desc.add_capability_list(capa_list_url)

    def report(self):
        """
        Keep track of filed files and packaged resources, echo the results of this run to the console.
        """
        synced_files_def = 0
        synced_files_end = 0
        synced_files_path = os.path.join(self.sink_dir, FILE_SYNCED_FILES)
        if os.path.isfile(synced_files_path):
            with open(synced_files_path, "r") as sfile:
                line = sfile.read()
                items = line.split(",")
                synced_files_def = int(items[0])
                synced_files_end = int(items[1])

        total_files_def = synced_files_def + self.total_count_def_resources
        total_files_end = synced_files_end + self.total_diff_end_resources
        total_files = total_files_def + total_files_end

        with open(synced_files_path, "w") as sfile:
            sfile.write("%d,%d" % (total_files_def, total_files_end))

        filed_files = 0
        filed_files_path = os.path.join(self.source_dir, FILE_FILED_FILES)
        if os.path.isfile(filed_files_path):
            with open(filed_files_path, "r") as ffile:
                filed_files = int(ffile.read())
        else:
            print "WARNING: %s not found. Unable to account for number of files filed and/or exported." % filed_files_path

        if self.total_count_def_resources != 0 or self.total_diff_end_resources !=0:
            print "Synchronized %d files in packages %s and %d files in package %s" \
                  % (self.total_count_def_resources, PREFIX_COMPLETED_PART, self.total_diff_end_resources, PREFIX_END_PART)
        else:
            print "No changes"

        if filed_files != total_files:
            print "WARNING: Accounting files is out of sync. Files filed: %d, resources synchronized %d" \
                  % (filed_files, total_files)

        print "Synchronized since %s: %d + %d = \t %d resources" \
              % (self.handshake, total_files_def, total_files_end, total_files)



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

        path_publish_handshake = os.path.join(self.sink_dir, FILE_HANDSHAKE)
        if os.path.isfile(path_publish_handshake):
            with open(path_publish_handshake, "r") as r_file:
                publish_handshake = r_file.read()

        if resource_handshake is None:
            print "WARNING: No source handshake found. Not interfering with status quo of published resources."
            return None

        if publish_handshake is None:
            # This can only be at the very start of synchronizing with a fresh empty publish_dir
            if self.walk_publish_dir() > 0:
                print "Error: No publish handshake found and %s not empty. " \
                      "Not interfering with status quo of published resources." % self.sink_dir
                return None

        if resource_handshake != publish_handshake:
            print "Resource_handshake is %s, publish_handshake is % s. Shrubbing %s" \
                  % (resource_handshake, publish_handshake, self.sink_dir)
            self.walk_publish_dir(remove_our_files=True)
            publish_handshake = None

        if resource_handshake and publish_handshake is None:
            self.walk_publish_dir(remove_our_files=True)
            with open(path_publish_handshake, "w") as w_file:
                w_file.write(resource_handshake)
            print "Signed new handshake: %s" % resource_handshake

        return resource_handshake

    def walk_publish_dir(self, remove_our_files=False):
        """
        Count items in sink_dir that are created by resourcesync-generator
        :param remove_our_files: if True, remove any such items found
        :return: item count
        """
        our_things = 0
        for a_file in os.listdir(self.sink_dir):
            if self.is_our_file(a_file):
                our_things += 1
                if remove_our_files:
                    file_path = os.path.join(self.sink_dir, a_file)
                    if os.path.isfile(file_path):
                        os.remove(file_path)
                    elif os.path.isdir(file_path):
                        shutil.rmtree(file_path)
        return our_things

    def is_our_file(self, a_file):
        return a_file.startswith((FILE_HANDSHAKE,
                                  FILE_INDEX,
                                  FILE_SYNCED_FILES,
                                  PATTERN_RDF_OUT,
                                  RS_RESOURCE_DUMP_XML,
                                  RS_CAPABILITY_LIST_XML,
                                  PREFIX_MANIFEST,
                                  PREFIX_COMPLETED_PART,
                                  PREFIX_END_PART)) \
               or os.path.isdir(os.path.join(self.sink_dir, a_file))