
import os, shutil, unittest, synchronizer
from synchronizer import Synchronizer
from glob import glob


class TestSynchronizer(unittest.TestCase):

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

        syncer = Synchronizer(resource_dir, publish_dir, publish_url)
        syncer.publish()

        self.assertTrue(os.path.isdir(publish_dir))

    def test_not_publish_last_dump_file(self):
        resource_dir = self.copy_files(["rdfdump-00001", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        syncer = Synchronizer(resource_dir, publish_dir, publish_url)
        syncer.publish()

        zip_end_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_END_ZIP + "*.zip"))
        self.assertEqual(0, len(zip_end_files))

    def test_publish_dump_files(self):
        resource_dir = self.copy_files(["rdfdump-00001", "rdfdump-00002", "rdfdump-00003", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        syncer = Synchronizer(resource_dir, publish_dir, publish_url)
        syncer.publish()

        zip_end_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_END_ZIP + "*.zip"))
        self.assertEqual(1, len(zip_end_files))
        # 2 rdfdump files in zip

    def test_publish_incremental_zips(self):
        resource_dir = self.copy_files(["rdfdump-00001", "rdfdump-00002", "rdfdump-00003", "rdfdump-99999",
            "rdfpatch-20160113072513", "rdfpatch-20160113082513", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")
        shutil.rmtree(publish_dir, ignore_errors=True)

        syncer = Synchronizer(resource_dir, publish_dir, publish_url, max_files_in_zip=2)
        syncer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_COMPLETED_ZIP + "*.zip"))
        self.assertEqual(2, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_END_ZIP + "*.zip"))
        self.assertEqual(0, len(zip_end_files))

        # add another file
        self.copy_files(["rdfpatch-20160712144328"], rmtree=False)
        syncer = Synchronizer(resource_dir, publish_dir, publish_url, max_files_in_zip=2)
        syncer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_COMPLETED_ZIP + "*.zip"))
        self.assertEqual(2, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_END_ZIP + "*.zip"))
        self.assertEqual(1, len(zip_end_files))

        # add another file
        self.copy_files(["rdfpatch-20160712145231"], rmtree=False)
        syncer = Synchronizer(resource_dir, publish_dir, publish_url, max_files_in_zip=2)
        syncer.publish()

        zip_completed_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_COMPLETED_ZIP + "*.zip"))
        self.assertEqual(3, len(zip_completed_files))
        zip_end_files = glob(os.path.join(publish_dir, synchronizer.PREFIX_END_ZIP + "*.zip"))
        self.assertEqual(0, len(zip_end_files))

    def test_verify_handshake_with_no_resource_handshake(self):
        resource_dir = self.copy_files(["rdfdump-00001"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")

        guinea_file = os.path.join(publish_dir, "test.txt")
        with open(guinea_file, "w") as w_file:
            w_file.write("some string")

        syncer = Synchronizer(resource_dir, publish_dir, publish_url)
        # should do nothing 'cause no resource_handshake
        handshake = syncer.verify_handshake()

        self.assertIsNone(handshake)
        self.assertTrue(os.path.isdir(publish_dir))
        self.assertTrue(os.path.isfile(guinea_file))

    def test_verify_handshake_with_no_resource_handshake_but_publish_handshake(self):
        resource_dir = self.copy_files(["rdfdump-00001"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")

        guinea_file = os.path.join(publish_dir, "test.txt")
        with open(guinea_file, "w") as w_file:
            w_file.write("some string")

        path_publish_handshake = os.path.join(publish_dir, synchronizer.FILE_HANDSHAKE)
        with open(path_publish_handshake, "w") as w_file:
            w_file.write("20160805110708")

        syncer = Synchronizer(resource_dir, publish_dir, publish_url)
        # should do nothing 'cause no resource_handshake
        handshake = syncer.verify_handshake()

        self.assertIsNone(handshake)
        self.assertTrue(os.path.isdir(publish_dir))
        self.assertTrue(os.path.isfile(guinea_file))
        self.assertTrue(os.path.isfile(path_publish_handshake))

    def test_verify_handshake_same_handshake(self):
        resource_dir = self.copy_files(["rdfdump-00001", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")

        guinea_file = os.path.join(publish_dir, "test.txt")
        with open(guinea_file, "w") as w_file:
            w_file.write("some string")

        path_publish_handshake = os.path.join(publish_dir, synchronizer.FILE_HANDSHAKE)
        with open(path_publish_handshake, "w") as w_file:
            w_file.write("20160805110708")

        syncer = Synchronizer(resource_dir, publish_dir, publish_url)
        # should do normal synchronizing
        handshake = syncer.verify_handshake()

        self.assertEqual("20160805110708", handshake)
        self.assertTrue(os.path.isdir(publish_dir))
        self.assertTrue(os.path.isfile(guinea_file))
        self.assertTrue(os.path.isfile(path_publish_handshake))

    def test_verify_handshake_shrubb(self):
        resource_dir = self.copy_files(["rdfdump-00001", "started_at.txt"])
        publish_url = "http://example.com/rdf/pub/"
        publish_dir = os.path.expanduser("~/tmp/zipper_test/dump")

        guinea_file = os.path.join(publish_dir, "test.txt")
        with open(guinea_file, "w") as w_file:
            w_file.write("some string")

        path_publish_handshake = os.path.join(publish_dir, synchronizer.FILE_HANDSHAKE)
        with open(path_publish_handshake, "w") as w_file:
            w_file.write("20150805110708")

        syncer = Synchronizer(resource_dir, publish_dir, publish_url)
        # should do normal synchronizing
        handshake = syncer.verify_handshake()

        self.assertEqual("20160805110708", handshake)
        self.assertTrue(os.path.isdir(publish_dir))
        self.assertTrue(os.path.isfile(guinea_file))
        self.assertTrue(os.path.isfile(path_publish_handshake))
        with open(path_publish_handshake, "r") as r_file:
            publish_handshake = r_file.read()

        self.assertEqual(handshake, publish_handshake)




