"""Off-chain helper of the CredentiaChain prototype (invented data only).

Educational project for the course Introduction to Finance.
Not a real product, service or investment offer. Do not use with real funds.

It builds the canonical text of a document and returns the salted SHA-256 hash that the
issuer registers on the blockchain. The hash is computed from the document CONTENT, not
from a scan, and a random salt stops anyone from guessing an IIN from the hash.
"""
import hashlib
import secrets
import sys

FIELDS = ("doc_number", "issuer_bin", "holder_iin", "issue_date")


def canonical(doc: dict, salt: str) -> bytes:
    """Fixed field order, no extra spaces, UTF-8 -> the same bytes on every machine."""
    parts = [str(doc[f]).strip() for f in FIELDS] + [salt]
    return "|".join(parts).encode("utf-8")


def document_hash(doc: dict, salt: str) -> str:
    return "0x" + hashlib.sha256(canonical(doc, salt)).hexdigest()


def new_salt() -> str:
    return secrets.token_hex(16)  # printed only in the holder's QR code


if __name__ == "__main__":
    # invented example, no real person or organisation
    demo = {"doc_number": "TEST-DOC-0001", "issuer_bin": "BIN000000000",
            "holder_iin": "IIN-FAKE-0001", "issue_date": "2026-06-30"}
    salt = sys.argv[1] if len(sys.argv) > 1 else new_salt()
    print(document_hash(demo, salt))
