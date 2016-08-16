
import os, shutil, unittest
from zipsynchronizer import ZipSynchronizer
from synchronizer import PREFIX_END_PART, PREFIX_COMPLETED_PART
from glob import glob


class TestZipSynchronizer(unittest.TestCase):

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
        resource_dir = self.copy_files(["started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        syncer = ZipSynchronizer(resource_dir, publish_dir, publish_url)
        syncer.publish()

        self.assertTrue(os.path.isdir(publish_dir))

    def test_not_publish_last_dump_file(self):
        resource_dir = self.copy_files(["rdfpatch-0d000000000001", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        syncer = ZipSynchronizer(resource_dir, publish_dir, publish_url)
        syncer.publish()

        zip_end_files = glob(os.path.join(publish_dir, PREFIX_END_PART + "*.zip"))
        self.assertEqual(0, len(zip_end_files))

    def test_publish_dump_files(self):
        resource_dir = self.copy_files(["rdfpatch-0d000000000001", "rdfpatch-0d000000000002", "rdfpatch-0d000000000003", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        syncer = ZipSynchronizer(resource_dir, publish_dir, publish_url)
        syncer.publish()

        zip_end_files = glob(os.path.join(publish_dir, PREFIX_END_PART + "*.zip"))
        self.assertEqual(1, len(zip_end_files))
        # 2 rdfdump files in zip

    def test_publish_incremental_zips(self):
        resource_dir = self.copy_files(["rdfpatch-0d000000000001", "rdfpatch-0d000000000002", "rdfpatch-0d000000000003", "rdfpatch-99999999999999",
            "rdfpatch-20140101010101", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        syncer = ZipSynchronizer(resource_dir, publish_dir, publish_url, max_files_compressed=2)
        syncer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, PREFIX_COMPLETED_PART + "*.zip"))
        self.assertEqual(2, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, PREFIX_END_PART + "*.zip"))
        self.assertEqual(0, len(zip_end_files))

        # add another file
        self.copy_files(["rdfpatch-20150101010101"], rmtree=False)
        syncer = ZipSynchronizer(resource_dir, publish_dir, publish_url, max_files_compressed=2)
        syncer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, PREFIX_COMPLETED_PART + "*.zip"))
        self.assertEqual(2, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, PREFIX_END_PART + "*.zip"))
        self.assertEqual(1, len(zip_end_files))

        # add another file
        self.copy_files(["rdfpatch-20160101010101"], rmtree=False)
        syncer = ZipSynchronizer(resource_dir, publish_dir, publish_url, max_files_compressed=2)
        syncer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, PREFIX_COMPLETED_PART + "*.zip"))
        self.assertEqual(3, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, PREFIX_END_PART + "*.zip"))
        self.assertEqual(0, len(zip_end_files))





