
import os, shutil, unittest
from synchronizer import Synchronizer
from glob import glob


class TestZipper(unittest.TestCase):

    def copy_files(self, files, rmtree=True):
        src_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__name__))), "sample")
        dst_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__name__))), "sample", "test")
        if rmtree:
            shutil.rmtree(dst_dir, ignore_errors=True)

        if not os.path.isdir(dst_dir):
            os.makedirs(dst_dir)

        for filename in files:
            src = os.path.join(src_dir, filename)
            shutil.copy(src, dst_dir)

        return dst_dir

    def test_publish_zero_resources(self):
        resource_dir = self.copy_files([])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        synchronizer = Synchronizer(resource_dir, publish_dir, publish_url)
        synchronizer.publish()

        self.assertTrue(os.path.isdir(publish_dir))

    def test_not_publish_last_dump_file(self):
        resource_dir = self.copy_files(["rdfdump-00001"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        synchronizer = Synchronizer(resource_dir, publish_dir, publish_url)
        synchronizer.publish()

        zip_end_files = glob(os.path.join(publish_dir, synchronizer.prefix_end_zip + "*.zip"))
        self.assertEqual(0, len(zip_end_files))

    def test_publish_dump_files(self):
        resource_dir = self.copy_files(["rdfdump-00001", "rdfdump-00002", "rdfdump-00003"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        synchronizer = Synchronizer(resource_dir, publish_dir, publish_url)
        synchronizer.publish()

        zip_end_files = glob(os.path.join(publish_dir, synchronizer.prefix_end_zip + "*.zip"))
        self.assertEqual(1, len(zip_end_files))
        # 2 rdfdump files in zip

    def test_publish_incremental_zips(self):
        resource_dir = self.copy_files(["rdfdump-00001", "rdfdump-00002", "rdfdump-00003", "rdfdump-99999",
            "rdfpatch-20160113072513", "rdfpatch-20160113082513"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        synchronizer = Synchronizer(resource_dir, publish_dir, publish_url, max_files_in_zip=2)
        synchronizer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, synchronizer.prefix_completed_zip + "*.zip"))
        self.assertEqual(2, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, synchronizer.prefix_end_zip + "*.zip"))
        self.assertEqual(0, len(zip_end_files))

        # add another file
        self.copy_files(["rdfpatch-20160712144328"], rmtree=False)
        synchronizer = Synchronizer(resource_dir, publish_dir, publish_url, max_files_in_zip=2)
        synchronizer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, synchronizer.prefix_completed_zip + "*.zip"))
        self.assertEqual(2, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, synchronizer.prefix_end_zip + "*.zip"))
        self.assertEqual(1, len(zip_end_files))

        # add another file
        self.copy_files(["rdfpatch-20160712145231"], rmtree=False)
        synchronizer = Synchronizer(resource_dir, publish_dir, publish_url, max_files_in_zip=2)
        synchronizer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, synchronizer.prefix_completed_zip + "*.zip"))
        self.assertEqual(3, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, synchronizer.prefix_end_zip + "*.zip"))
        self.assertEqual(0, len(zip_end_files))





