import unittest
from hash_document import document_hash

DOC = {"doc_number": "TEST-DOC-0001", "issuer_bin": "BIN000000000",
       "holder_iin": "IIN-FAKE-0001", "issue_date": "2026-06-30"}


class HashTests(unittest.TestCase):
    def test_same_content_same_hash(self):
        self.assertEqual(document_hash(DOC, "s1"), document_hash(dict(DOC), "s1"))

    def test_one_changed_character_changes_hash(self):
        other = dict(DOC, issue_date="2026-06-29")
        self.assertNotEqual(document_hash(DOC, "s1"), document_hash(other, "s1"))

    def test_salt_changes_hash(self):
        self.assertNotEqual(document_hash(DOC, "s1"), document_hash(DOC, "s2"))


if __name__ == "__main__":
    unittest.main()
