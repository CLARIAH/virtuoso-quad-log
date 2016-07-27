#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import os, re, shutil, resync.w3c_datetime as w3cdt
from resync.dump import Dump
from resync.resource import Resource
from resync.resource_list import ResourceList
from resync.utils import compute_md5_for_file
from resync.sitemap import Sitemap
from resync.resource_dump import ResourceDump
from resync.resource_dump_manifest import ResourceDumpManifest
from resync.capability_list import CapabilityList
from resync.source_description import SourceDescription
from glob import glob

# Alternative strategy to publish rdf patch files as resource dumps.

PREFIX_COMPLETED_ZIP = "part_"
PREFIX_END_ZIP = "zip_end_"
PREFIX_MANIFEST = "manifest_"


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

    def __init__(self, resource_dir, publish_dir, publish_url, max_files_in_zip=50000, write_separate_manifest=True,
                 move_resources=False):
        """
        Initialize a new Synchronizer.
        :param resource_dir: the source directory for resources
        :param publish_dir: the directory resources should be published to
        :param publish_url: public url pointing to publish dir
        :param max_files_in_zip: the maximum number of resource files that should be compressed in one zip file
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
        if max_files_in_zip > 50000:
            raise RuntimeError("%s exceeds limit of 50000 items per document of the Sitemap protocol." % str(max_files_in_zip))
        self.max_files_in_zip = max_files_in_zip
        self.write_separate_manifest = write_separate_manifest
        self.move_resources = move_resources

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
        if not os.path.isdir(self.resource_dir):
            os.makedirs(self.resource_dir)
            print "Created %s" % self.resource_dir

        if not os.path.isdir(self.publish_dir):
            os.makedirs(self.publish_dir)
            print "Created %s" % self.publish_dir

        path_zip_end_old, rl_end_old = self.get_state_published()
        new_zips = ResourceDump()
        state_changed = False
        exhausted = False

        while not exhausted:
            resourcelist, exhausted = self.list_resources_chunk()

            if len(resourcelist) == self.max_files_in_zip:  # complete zip
                state_changed = True
                zip_resource = self.create_zip(resourcelist, PREFIX_COMPLETED_ZIP, False,
                                               self.write_separate_manifest)
                new_zips.add(zip_resource)
                # move resources from resource_dir
                for resource in resourcelist:
                    r_path = os.path.join(self.resource_dir, resource.path)
                    if self.move_resources:
                        shutil.move(r_path, self.publish_dir)
                    else:
                        os.remove(r_path)
            elif not self.is_same(resourcelist, rl_end_old):
                assert exhausted
                state_changed = True
                if len(resourcelist) > 0:
                    zip_resource = self.create_zip(resourcelist, PREFIX_END_ZIP, True,
                                                   self.write_separate_manifest)
                    new_zips.add(zip_resource)

        # publish new metadata. Exclude zip_end_old
        if state_changed:
            self.publish_metadata(new_zips, path_zip_end_old)

        # remove old zip end file, resource list and manifest.
        if state_changed and path_zip_end_old:
            os.remove(path_zip_end_old)
            os.remove(os.path.splitext(path_zip_end_old)[0] + ".xml")
            manifest = PREFIX_MANIFEST + os.path.splitext(os.path.basename(path_zip_end_old))[0] + ".xml"
            manifest_file = os.path.join(self.publish_dir, manifest)
            if os.path.isfile(manifest_file):
                os.remove(manifest_file)

        if not state_changed:
            print "No changes"

    def publish_metadata(self, new_zips, exluded_zip=None):
        """
        (Re)publish metadata with addition of new_zips. An excluded zip will be removed from previously published
        metadata.
        :param new_zips: a resourcelist with newly created zip resources
        :param exluded_zip: local path to zip file that will be removed from previously published metadata.
        :return: None
        """
        rs_dump_url = self.publish_url + "resource-dump.xml"
        rs_dump_path = os.path.join(self.publish_dir, "resource-dump.xml")
        capa_list_url = self.publish_url + "capability-list.xml"
        capa_list_path = os.path.join(self.publish_dir, "capability-list.xml")
        src_desc_url = self.publish_url + ".well-known/resourcesync"
        src_desc_path = os.path.join(self.publish_dir, ".well-known", "resourcesync")

        rs_dump = ResourceDump()

        # Load existing resource-dump, if any. Else set start time.
        if os.path.isfile(rs_dump_path):
            with open(rs_dump_path, "r") as rs_dump_file:
                sm = Sitemap()
                sm.parse_xml(rs_dump_file, resources=rs_dump)

        else:
            rs_dump.md_at = w3cdt.datetime_to_str(no_fractions=True)
            rs_dump.link_set(rel="up", href=capa_list_url)

        # Remove excluded zip, if any
        if exluded_zip:
            loc = self.publish_url + os.path.basename(exluded_zip)
            if loc in rs_dump.resources:
                del rs_dump.resources[loc]
            else:
                raise RuntimeError("Could not find %s in %s" % (loc, rs_dump_path))

        # Add new zips
        for resource in new_zips:
            rs_dump.add(resource)

        # Write resource-dump.xml
        rs_dump.md_completed = w3cdt.datetime_to_str(no_fractions=True)
        with open(rs_dump_path, "w") as rs_dump_file:
            rs_dump_file.write(rs_dump.as_xml())

        print "Published %d dumps in %s. See %s" % (len(rs_dump), rs_dump_path, rs_dump_url)

        # Write capability-list.xml
        if not os.path.isfile(capa_list_path):
            capa_list = CapabilityList()
            capa_list.link_set(rel="up", href=src_desc_url)
            capa_list.add_capability(rs_dump, rs_dump_url)
            with open(capa_list_path, "w") as capa_list_file:
                capa_list_file.write(capa_list.as_xml())

            print "Published capability list. See %s" % capa_list_url

        # Write resourcesync
        wellknown = os.path.dirname(src_desc_path)
        if not os.path.isdir(wellknown):
            os.makedirs(wellknown)

        if not os.path.isfile(src_desc_path):
            src_desc = SourceDescription()
            src_desc.add_capability_list(capa_list_url)
            with open(src_desc_path, "w") as src_desc_file:
                src_desc_file.write(src_desc.as_xml())

            print "Published resource description. See %s" % src_desc_url

    def get_state_published(self):
        """
        See if publish_dir has a zip end file. If so, return the path of the zip end file and the resourcelist
        (with local paths) of resources published in the zip end file.
        :return:    - the path to the zip end file or None if there is no zip end file.
                    - the resourcelist of resources published in zip end file or an empty list if there is no zip end file.
        """
        path_zip_end_old = None
        rl_end_old = ResourceList()

        zip_end_files = glob(os.path.join(self.publish_dir, PREFIX_END_ZIP + "*.zip"))
        if len(zip_end_files) > 1:
            raise RuntimeError("Found more than one %s*.zip files. Inconsistent structure of %s."
                               % (PREFIX_END_ZIP, self.publish_dir))
        elif len(zip_end_files) == 1:
            path_zip_end_old = zip_end_files[0]

        if path_zip_end_old:
            rl_file = open(os.path.splitext(path_zip_end_old)[0] + ".xml", "r")
            sm = Sitemap()
            sm.parse_xml(rl_file, resources=rl_end_old)
            rl_file.close()

        return path_zip_end_old, rl_end_old

    def create_zip(self, resourcelist, prefix, write_list=False, write_manifest=True):
        """
        Dump local resources in resourcelist to a zip file with the specified prefix. The index in the zip file name
        will be 1 higher than the last zip file index with the same prefix. A manifest.xml will be included in the
        zip.
        --  The resync.Dump.write_zip method used in this method has the side effect of changing local paths in
            resourcelist into paths relative in zip.
        :param resourcelist: resources to zip
        :param prefix: prefix of the zip file
        :param write_list: True if resourcelist should be written to local disc. Default: False
        :param write_manifest: True if a separate manifest file should be written to disc, False otherwise. Default: True
        :return: the created zip as a resync.Resource.
        """
        md_at = None  # w3cdt.datetime_to_str(no_fractions=True) # attribute gets lost in read > write cycle with resync library.
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
        dump.write_zip(resourcelist, zip_path)  # paths in resourcelist will be stripped.
        md_completed = None  # w3cdt.datetime_to_str(no_fractions=True) # attribute gets lost in read > write cycle with resync library.
        print "Zipped %d resources in %s" % (len(resourcelist), zip_path)

        loc = self.publish_url + zip_name + ".zip"  # mandatory
        lastmod = self.last_modified(resourcelist)  # optional
        md_type = "application/zip"                 # recommended
        md_length = os.stat(zip_path).st_size
        md5 = compute_md5_for_file(zip_path)

        zip_resource = Resource(uri=loc, lastmod=lastmod,
                                length=md_length, md5=md5, mime_type=md_type,
                                md_at=md_at, md_completed=md_completed)
        if write_manifest:
            rdm = ResourceDumpManifest(resources=resourcelist.resources)
            rdm_file = open(os.path.join(self.publish_dir, PREFIX_MANIFEST + zip_name + ".xml"), "w")
            rdm_url = self.publish_url + PREFIX_MANIFEST + zip_name + ".xml"
            rdm_file.write(rdm.as_xml())
            rdm_file.close()
            zip_resource.link_set(rel="content", href=rdm_url)

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
