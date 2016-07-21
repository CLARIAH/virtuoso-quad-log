
import os, re
from resync.dump import Dump
from resync.resource import Resource
from resync.resource_list import ResourceList
from resync.utils import compute_md5_for_file
from glob import glob


class Synchronizer(object):

    def __init__(self, resource_dir, resource_url, publish_dir,
                 max_files_in_zip=50000):
        """
        Takes care of presenting resources in accordance with the Resource Sync Framework.
        See: http://www.openarchives.org/rs/1.0/resourcesync
        :param resource_dir: the directory where resources reside
        :param resource_url: public url pointing to publish dir
        :param publish_dir: the directory resources should be published to
        :param max_files_in_zip: the maximum number of files that should be compressed in one zip file
        :return:
        """
        self.resource_dir = resource_dir
        self.resource_url = resource_url
        self.publish_dir = publish_dir
        self.max_files_in_zip = max_files_in_zip
        self.prefix_completed_zip = "part_"
        self.prefix_incomplete_zip = "zip_end_"

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

    def publish(self):

        if not os.path.isdir(self.publish_dir):
            os.makedirs(self.publish_dir)

        zip_end_old = None
        zip_end_files = glob(os.path.join(self.publish_dir, self.prefix_incomplete_zip + "*.zip"))
        if len(zip_end_files) > 1:
            raise RuntimeError("Found more than one %s*.zip files. Inconsistent structure of %s."
                               % (self.prefix_incomplete_zip, self.publish_dir))
        elif len(zip_end_files) == 1:
            zip_end_old = zip_end_files[0]

        tel = 0
        exhausted = False
        while not exhausted:
            resourcelist = ResourceList()
            tel += 1
            exhausted = self.dump_list(resourcelist, max_files=self.max_files_in_zip)
            max_files = self.max_files_in_zip - len(resourcelist)
            if max_files > 0:
                patch_exhausted = self.patch_list(resourcelist, max_files=max_files)
                exhausted = exhausted and patch_exhausted

            if len(resourcelist) == self.max_files_in_zip:
                self.create_zip(resourcelist, self.prefix_completed_zip)
                # remove resources from resource_dir
                for resource in resourcelist:
                    os.remove(os.path.join(self.resource_dir, resource.path))
            elif len(resourcelist) > 0:
                self.create_zip(resourcelist, self.prefix_incomplete_zip)

        # publish new metadata except zip_end_old

        # remove old incomplete zip file
        if not zip_end_old is None:
            os.remove(zip_end_old)

    def create_zip(self, resourcelist, prefix):

        index = -1

        zipfiles = sorted(glob(os.path.join(self.publish_dir, prefix + "*.zip")))
        if len(zipfiles) > 0:
            last_zip_file = zipfiles[len(zipfiles) - 1]
            basename = os.path.basename(last_zip_file)
            index = int(re.findall('\d+', basename)[0])

        zip_name = "%s%010d" % (prefix, index + 1)
        zip_path = os.path.join(self.publish_dir, zip_name + ".zip")
        dump = Dump()
        dump.path_prefix = self.resource_dir
        dump.write_zip(resourcelist, zip_path)

        return zip_path

    def dump_list(self, resourcelist, max_files=-1):
        """
        Append resources to a ResourceList and compute the timestamp of the rdfdump-* files. All resources in
        resource_dir are included except for the last one in alphabetical sort order. If max_files is set to a
        value greater than 0, will only include up to max_files.
        :return: the ResourceList and the timestamps of the resources.
        """

        # Add dump files to the resource list. Last modified for all these files is the time dump was executed.
        # Last modified is recorded in the header of each file in a line starting with '# at checkpoint'.
        t = None
        dumpfiles = sorted(glob(os.path.join(self.resource_dir, "rdfdump-*")))
        if len(dumpfiles) > 0:
            dumpfiles.pop() # remove last from the list
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
            resourcelist.add(Resource(self.resource_url + filename, md5=md5, length=length, lastmod=timestamp, path=file))
            n += 1
            if 0 < max_files == n:
                break

        exhausted = len(dumpfiles) == n
        return exhausted

    def patch_list(self, resourcelist, max_files=-1):
        """

        :param resourcelist:
        :param timestamps:
        :param max_files:
        :return:
        """
        patchfiles = sorted(glob(os.path.join(self.resource_dir, "rdfpatch-*")))
        if len(patchfiles) > 0:
            patchfiles.pop() # remove last from list
        n = 0
        for file in patchfiles:
            filename = os.path.basename(file)
            _, raw_ts = filename.split("-")
            timestamp = self.compute_timestamp(raw_ts)
            length = os.stat(file).st_size
            md5 = compute_md5_for_file(file)
            resourcelist.add(Resource(self.resource_url + filename, md5=md5, length=length, lastmod=timestamp, path=file))
            n += 1
            if 0 < max_files == n:
                break

        exhausted = len(patchfiles) == n
        return exhausted



