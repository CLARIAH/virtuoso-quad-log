#! /usr/bin/env python2
# -*- coding: utf-8 -*-

import os, re, shutil, base64, resync.w3c_datetime as w3cdt
from glob import glob
from synchronizer import Synchronizer, PREFIX_MANIFEST, PREFIX_COMPLETED_PART, PREFIX_END_PART, \
    RS_RESOURCE_DUMP_XML, RS_CAPABILITY_LIST_XML
from resync.dump import Dump
from resync.resource import Resource
from resync.resource_list import ResourceList
from resync.sitemap import Sitemap
from resync.resource_dump import ResourceDump
from resync.resource_dump_manifest import ResourceDumpManifest
from resync.capability_list import CapabilityList
from resync.utils import compute_md5_for_file

# Strategy to publish rdf patch files as resource dumps in g-zip format.


class ZipSynchronizer(Synchronizer):
    """
    Takes care of presenting resources in accordance with the Resource Sync Framework as g-zipped resources.
    See: http://www.openarchives.org/rs/1.0/resourcesync


    http://www.openarchives.org/rs/1.0/resourcesync#DocumentFormats

        Sitemap Document Formats
        ... The ResourceSync framework follows community-defined limits for when to publish multiple documents of
        the <urlset> format. At time of publication of this specification, the limit is 50,000 items per document
        and a document size of 50 MB. ...
    """

    def __init__(self, resource_dir, publish_dir, publish_url,
                 src_desc_url=None,
                 max_files_compressed=50000,
                 write_separate_manifest=True,
                 move_resources=False):
        """
        Initialize a new ZipSynchronizer.
        :param resource_dir: the source directory for resources
        :param publish_dir: the directory resources should be published to
        :param publish_url: public url pointing to publish dir
        :param src_desc_url: public url pointing to resource description
        :param max_files_compressed: the maximum number of resource files that should be compressed in one zip file
        :param write_separate_manifest: will each zip file be accompanied by a separate resourcedump manifest.
        :param move_resources: Do we move the zipped resources to publish_dir or simply delete them from resource_dir.
        :return:
        """
        Synchronizer.__init__(self, resource_dir, publish_dir, publish_url, src_desc_url, max_files_compressed,
                              write_separate_manifest, move_resources)

    def publish(self):
        """
        Try and publish or remove zip end if something went wrong.

        :return: (  boolean indicating if change in sink directory or subdirectories,
                    amount of resources definitively packaged,
                    the difference of resources provisionally packaged)
        """
        if not os.path.isdir(self.resource_dir):
            os.makedirs(self.resource_dir)
            #print "Created %s" % self.resource_dir

        if not os.path.isdir(self.publish_dir):
            os.makedirs(self.publish_dir)
            #print "Created %s" % self.publish_dir

        try:
            return self.do_publish()
        except:
            # Something went wrong. Best we can do is clean up end of zip chain.
            zip_end_files = glob(os.path.join(self.publish_dir, PREFIX_END_PART + "*.zip"))
            for ze_file in zip_end_files:
                os.remove(ze_file)
                print "error recovery: removed %s" % ze_file

            zip_end_xmls = glob(os.path.join(self.publish_dir, PREFIX_END_PART + "*.xml"))
            for ze_xml in zip_end_xmls:
                os.remove(ze_xml)
                print "error recovery: removed %s" % ze_xml

            zip_end_manis = glob(
                os.path.join(self.publish_dir,
                             PREFIX_MANIFEST + PREFIX_END_PART + "*.xml"))
            for ze_mani in zip_end_manis:
                os.remove(ze_mani)
                print "error recovery: removed %s" % ze_mani

            # remove zip-end entries from resource-dump.xml
            rs_dump_path = os.path.join(self.publish_dir, RS_RESOURCE_DUMP_XML)
            rs_dump = ResourceDump()
            if os.path.isfile(rs_dump_path):
                with open(rs_dump_path, "r") as rs_dump_file:
                    sm = Sitemap()
                    sm.parse_xml(rs_dump_file, resources=rs_dump)

            prefix = self.publish_url + PREFIX_END_PART

            for uri in rs_dump.resources.keys():
                if uri.startswith(prefix):
                    del rs_dump.resources[uri]
                    print "error recovery: removed %s from %s" % (uri, rs_dump_path)

            with open(rs_dump_path, "w") as rs_dump_file:
                rs_dump_file.write(rs_dump.as_xml())

            print "error recovery: walk through error recovery completed. Now raising ..."
            raise

    def do_publish(self):
        """
        Publish resources found in resource_dir in accordance with the Resource Sync Framework.
        Resources will be packaged in ZIP file format. The amount of resources that will be packaged in one zip file
        is bound to max_files_in_zip. Successive packages will be created if more than max_files_in_zip resources
        have to be published. Packages that reach the limit of max_files_in_zip are marked as complete. Any remainder
        of resources are packaged in a zip file marked as zip end.

        WARNING: This method removes resources that are published in packages marked as complete from resource_dir.

        :return: (  boolean indicating if change in sink directory or subdirectories,
                    amount of resources definitively packaged,
                    the difference of resources provisionally packaged)
        """
        count_def_resources = 0
        diff_end_resources = 0
        path_zip_end_old, rl_end_old = self.get_state_published()

        new_zips = ResourceDump()
        state_changed = False
        exhausted = False

        while not exhausted:
            resourcelist, exhausted = self.list_resources_chunk()

            if len(resourcelist) == self.max_files_compressed:  # complete zip
                state_changed = True
                count_def_resources += len(resourcelist)
                zip_resource = self.create_zip(resourcelist, PREFIX_COMPLETED_PART, False,
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
                    diff_end_resources += len(resourcelist)
                    zip_resource = self.create_zip(resourcelist, PREFIX_END_PART, True,
                                                   self.write_separate_manifest)
                    new_zips.add(zip_resource)

        # publish new metadata. Exclude zip_end_old
        if state_changed:
            self.publish_metadata(new_zips, path_zip_end_old)

        # remove old zip end file, resource list and manifest;
        # account for difference of resources provisionally packaged.
        if state_changed and path_zip_end_old:
            diff_end_resources -= len(rl_end_old)
            os.remove(path_zip_end_old)
            os.remove(os.path.splitext(path_zip_end_old)[0] + ".xml")
            manifest = PREFIX_MANIFEST + os.path.splitext(os.path.basename(path_zip_end_old))[0] + ".xml"
            manifest_file = os.path.join(self.publish_dir, manifest)
            if os.path.isfile(manifest_file):
                os.remove(manifest_file)

        return state_changed, count_def_resources, diff_end_resources

    def publish_metadata(self, new_zips, exluded_zip=None):
        """
        (Re)publish metadata with addition of new_zips. An excluded zip will be removed from previously published
        metadata.
        :param new_zips: a resourcelist with newly created zip resources
        :param exluded_zip: local path to zip file that will be removed from previously published metadata.
        """
        rs_dump_url = self.publish_url + RS_RESOURCE_DUMP_XML
        rs_dump_path = os.path.join(self.publish_dir, RS_RESOURCE_DUMP_XML)
        capa_list_url = self.publish_url + RS_CAPABILITY_LIST_XML
        capa_list_path = os.path.join(self.publish_dir, RS_CAPABILITY_LIST_XML)

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

        # There are several ways to decode base64, among them
        # iri = base64.b64decode(os.path.basename(self.publish_dir)).rstrip('\n')
        # iri = base64.b64decode(os.path.basename(self.publish_dir), '-_').rstrip('\n')
        iri = base64.urlsafe_b64decode(os.path.basename(self.publish_dir)).rstrip('\n')

        print "New %s for graph %s" % (RS_RESOURCE_DUMP_XML, iri)
        print "See %s" % rs_dump_url

        # Write capability-list.xml
        if not os.path.isfile(capa_list_path):
            capa_list = CapabilityList()
            capa_list.link_set(rel="up", href=self.src_desc_url)
            capa_list.add_capability(rs_dump, rs_dump_url)
            with open(capa_list_path, "w") as capa_list_file:
                capa_list_file.write(capa_list.as_xml())

            print "New %s. See %s" % (RS_CAPABILITY_LIST_XML, capa_list_url)

    def get_state_published(self):
        """
        See if publish_dir has a zip end file. If so, return the path of the zip end file and the resourcelist
        (with local paths) of resources published in the zip end file.
        :return:    - the path to the zip end file or None if there is no zip end file.
                    - the resourcelist of resources published in zip end file or an empty list if there is no zip end file.
        """
        path_zip_end_old = None
        rl_end_old = ResourceList()

        zip_end_files = glob(os.path.join(self.publish_dir, PREFIX_END_PART + "*.zip"))
        if len(zip_end_files) > 1:
            raise RuntimeError("Found more than one %s*.zip files. Inconsistent structure of %s."
                               % (PREFIX_END_PART, self.publish_dir))
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
        #print "Zipped %d resources in %s" % (len(resourcelist), zip_path)

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




