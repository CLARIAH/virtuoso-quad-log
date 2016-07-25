#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import os, re, resync.w3c_datetime as w3cdt
from resync.dump import Dump
from resync.resource import Resource
from resync.resource_list import ResourceList
from resync.utils import compute_md5_for_file
from resync.sitemap import Sitemap
from resync.resource_dump import ResourceDump
from resync.capability_list import CapabilityList
from resync.source_description import SourceDescription
from glob import glob

# Alternative strategy to publish rdf patch files as resource dumps. Not implemented.

class Synchronizer(object):
    """
    Takes care of presenting resources in accordance with the Resource Sync Framework.
    See: http://www.openarchives.org/rs/1.0/resourcesync


    http://www.openarchives.org/rs/1.0/resourcesync#DocumentFormats

        Sitemap Document Formats
        ... The ResourceSync framework follows community-defined limits for when to publish multiple documents of
        the <urlset> format. At time of publication of this specification, the limit is 50,000 items per document
        and a document size of 50 MB. ...
    """

    def __init__(self, resource_dir, publish_dir, publish_url, max_files_in_zip=50000):
        """
        Initialize a new Synchronizer.
        :param resource_dir: the source directory for resources
        :param publish_dir: the directory resources should be published to
        :param publish_url: public url pointing to publish dir
        :param max_files_in_zip: the maximum number of resource files that should be compressed in one zip file
        :return:
        """
        if not os.path.isdir(resource_dir):
            raise IOError(resource_dir + " is not a directory")
        self.resource_dir = resource_dir
        self.publish_dir = publish_dir
        self.publish_url = publish_url
        if self.publish_url[-1] != '/':
            self.publish_url += '/'
        if max_files_in_zip > 50000:
            raise RuntimeError("max_files_in_zip exceeds limit of 50000 items per document of the Sitemap protocol.")
        self.max_files_in_zip = max_files_in_zip
        self.prefix_completed_zip = "part_"
        self.prefix_end_zip = "zip_end_"

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
        lastmod = None
        for resource in resourcelist:
            rlm = resource.lastmod
            if rlm > lastmod:
                lastmod = rlm

        return lastmod

    def publish(self):
        """
        Publish resources found in resource_dir in accordance with the Resource Sync Framework.
        Resources will be packaged in ZIP file format. The amount of resources that will be packaged in one zip file
        is bound to max_files_in_zip. Successive packages will be created if more than max_files_in_zip resources
        have to be published. Packages that reach the limit of max_files_in_zip are marked as complete. Any remainder
        of resources are packaged in a zip file marked as zip end.

        WARNING: This method removes resources that are published in packages marked as complete from resource_dir.

        :return:
        """
        if not os.path.isdir(self.publish_dir):
            os.makedirs(self.publish_dir)

        path_zip_end_old, rl_end_old = self.get_state_published()
        new_zips = ResourceDump()
        state_changed = False
        exhausted = False

        while not exhausted:
            resourcelist, exhausted = self.list_resources_chunk()

            if len(resourcelist) == self.max_files_in_zip:  # complete zip
                state_changed = True
                zip_resource = self.create_zip(resourcelist, self.prefix_completed_zip)
                new_zips.add(zip_resource)
                # remove resources from resource_dir
                for resource in resourcelist:
                    os.remove(os.path.join(self.resource_dir, resource.path))
            elif not self.is_same(resourcelist, rl_end_old):
                assert exhausted
                state_changed = True
                if len(resourcelist) > 0:
                    zip_resource = self.create_zip(resourcelist, self.prefix_end_zip, True)
                    new_zips.add(zip_resource)

        # publish new metadata. Exclude zip_end_old
        if state_changed:
            self.publish_metadata(new_zips, path_zip_end_old)

        # remove old zip end file and resource list
        if state_changed and path_zip_end_old:
            os.remove(path_zip_end_old)
            os.remove(os.path.splitext(path_zip_end_old)[0] + ".xml")

    def publish_metadata(self, new_zips, exluded_zip):

        rs_dump_url = self.publish_url + "resource-dump.xml"
        rs_dump_path = os.path.join(self.publish_dir, "resource-dump.xml")
        capa_list_url = self.publish_url + "capability-list.xml"
        capa_list_path = os.path.join(self.publish_dir, "capability-list.xml")
        src_desc_url = self.publish_url + ".well-known/resourcesync"
        src_desc_path = os.path.join(self.publish_dir, ".well-known", "resourcesync")

        rs_dump = ResourceDump()

        # Load existing resource-dump, if any. Else set start time.
        if os.path.isfile(rs_dump_path):
            rs_dump_file = open(rs_dump_path, "r")
            sm = Sitemap()
            sm.parse_xml(rs_dump_file, resources=rs_dump)
            rs_dump_file.close()
        else:
            rs_dump.md_at = w3cdt.datetime_to_str()
            rs_dump.link_set(rel="up", href=capa_list_url)

        # Remove excluded zip, if any
        if exluded_zip:
            loc = self.publish_url + os.path.basename(exluded_zip)
            del rs_dump.resources[loc]

        # Add new zips
        for resource in new_zips:
            rs_dump.add(resource)

        # Write resource-dump.xml
        rs_dump.md_completed = w3cdt.datetime_to_str()
        rs_dump_file = open(rs_dump_path, "w")
        rs_dump_file.write(rs_dump.as_xml())
        rs_dump_file.close()

        # Write capability-list.xml
        if not os.path.isfile(capa_list_path):
            capa_list = CapabilityList()
            capa_list.link_set(rel="up", href=src_desc_url)
            capa_list.add_capability(rs_dump, rs_dump_url)
            capa_list_file = open(capa_list_path, "w")
            capa_list_file.write(capa_list.as_xml())
            capa_list_file.close()

        # Write resourcesync
        wellknown = os.path.dirname(src_desc_path)
        if not os.path.isdir(wellknown):
            os.makedirs(wellknown)

        if not os.path.isfile(src_desc_path):
            src_desc = SourceDescription()
            src_desc.add_capability_list(capa_list_url)
            src_desc_file = open(src_desc_path, "w")
            src_desc_file.write(src_desc.as_xml())
            src_desc_file.close()

    def get_state_published(self):
        path_zip_end_old = None
        rl_end_old = ResourceList()

        zip_end_files = glob(os.path.join(self.publish_dir, self.prefix_end_zip + "*.zip"))
        if len(zip_end_files) > 1:
            raise RuntimeError("Found more than one %s*.zip files. Inconsistent structure of %s."
                               % (self.prefix_end_zip, self.publish_dir))
        elif len(zip_end_files) == 1:
            path_zip_end_old = zip_end_files[0]

        if not path_zip_end_old is None:
            rl_file = open(os.path.splitext(path_zip_end_old)[0] + ".xml", "r")
            sm = Sitemap()
            sm.parse_xml(rl_file, resources=rl_end_old)
            rl_file.close()

        return path_zip_end_old, rl_end_old

    def create_zip(self, resourcelist, prefix, write_list=False):

        md_at = None  # w3cdt.datetime_to_str() # attribute gets lost in read > write cycle with resync library.
        index = -1
        zipfiles = sorted(glob(os.path.join(self.publish_dir, prefix + "*.zip")))
        if len(zipfiles) > 0:
            last_zip_file = zipfiles[len(zipfiles) - 1]
            basename = os.path.basename(last_zip_file)
            index = int(re.findall('\d+', basename)[0])

        zip_name = "%s%05d" % (prefix, index + 1)
        if (write_list):
            # this is the given resourcelist with local paths. As such it is *not* the resourcedump_manifest.
            rl_file = open(os.path.join(self.publish_dir, zip_name + ".xml"), "w")
            rl_file.write(resourcelist.as_xml())
            rl_file.close()

        zip_path = os.path.join(self.publish_dir, zip_name + ".zip")
        dump = Dump()
        dump.path_prefix = self.resource_dir
        dump.write_zip(resourcelist, zip_path)
        md_completed = None  # w3cdt.datetime_to_str() # attribute gets lost in read > write cycle with resync library.

        loc = self.publish_url + zip_name + ".zip"  # mandatory
        lastmod = self.last_modified(resourcelist)  # optional
        md_type = "application/zip"                 # recommended
        md_length = os.stat(zip_path).st_size
        md5 = compute_md5_for_file(zip_path)

        zip_resource = Resource(uri=loc, lastmod=lastmod,
                                length=md_length, md5=md5, mime_type=md_type,
                                md_at=md_at, md_completed=md_completed)
        return zip_resource

    def list_resources_chunk(self):
        """
        Fill a resource list up to max_files_in_zip or with as much rdf-files as there are left in resource_dir.
        A boolean indicates whether the resource_dir was exhausted.
        :return: the ResourceList, exhausted
        """
        resourcelist = ResourceList()
        exhausted = self.list_dump_files(resourcelist, max_files=self.max_files_in_zip)
        max_files = self.max_files_in_zip - len(resourcelist)
        if max_files > 0:
            patch_exhausted = self.list_patch_files(resourcelist, max_files=max_files)
            exhausted = exhausted and patch_exhausted
        return resourcelist, exhausted

    def list_dump_files(self, resourcelist, max_files=-1):
        """
        Append resources of the rdfdump-* files to a resourcelist. All resources in
        resource_dir are included except for the last one in alphabetical sort order. If max_files is set to a
        value greater than 0, will only include up to max_files.
        :param resourcelist:
        :param max_files:
        :return: True if the list includes the one but last rdfdump-* file in resource_dir, False otherwise
        """

        # Add dump files to the resource list. Last modified for all these files is the time dump was executed.
        # Last modified is recorded in the header of each file in a line starting with '# at checkpoint'.
        t = None
        dumpfiles = sorted(glob(os.path.join(self.resource_dir, "rdfdump-*")))
        if len(dumpfiles) > 0:
            dumpfiles.pop()  # remove last from the list
        if len(dumpfiles) > 0:
            with open(dumpfiles[0]) as search:
                for line in search:
                    if re.match("# at checkpoint.*", line):
                        t = re.findall('\d+', line)[0]
                        break

            if t is None:
                raise RuntimeError("Found dump files but did not find timestamp for checkpoint in '%s'" % dumpfiles[0])

            timestamp = self.compute_timestamp(t)

        n = 0
        for file in dumpfiles:
            filename = os.path.basename(file)
            length = os.stat(file).st_size
            md5 = compute_md5_for_file(file)
            resourcelist.add(
                Resource(self.publish_url + filename, md5=md5, length=length, lastmod=timestamp, path=file))
            n += 1
            if 0 < max_files == n:
                break

        exhausted = len(dumpfiles) == n
        return exhausted

    def list_patch_files(self, resourcelist, max_files=-1):
        """
        Append resources of the rdfpatch-* files to a resourcelist. All resources in
        resource_dir are included except for the last one in alphabetical sort order. If max_files is set to a
        value greater than 0, will only include up to max_files.
        :param resourcelist:
        :param max_files:
        :return: True if the list includes the one but last rdfpatch-* file in resource_dir, False otherwise
        """
        patchfiles = sorted(glob(os.path.join(self.resource_dir, "rdfpatch-*")))
        if len(patchfiles) > 0:
            patchfiles.pop()  # remove last from list
        n = 0
        for file in patchfiles:
            filename = os.path.basename(file)
            _, raw_ts = filename.split("-")
            timestamp = self.compute_timestamp(raw_ts)
            length = os.stat(file).st_size
            md5 = compute_md5_for_file(file)
            resourcelist.add(
                Resource(self.publish_url + filename, md5=md5, length=length, lastmod=timestamp, path=file))
            n += 1
            if 0 < max_files == n:
                break

        exhausted = len(patchfiles) == n
        return exhausted
