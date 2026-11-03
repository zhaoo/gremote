#!/usr/bin/env python3
"""Run native envelope validation without requiring Xcode or UIKit."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'ios/Runner/Native/FilmLibraryDocument.swift').read_text()
tests = (root / 'ios/Tests/FilmLibraryDocumentTest.swift').read_text()
with tempfile.TemporaryDirectory(prefix='gremote-film-export-') as directory:
    script = Path(directory) / 'film_library_document_test.swift'
    script.write_text(source + '\n' + tests.replace('@main\n', '') +
                      '\ntry FilmLibraryDocumentTest.main()\n')
    subprocess.run(['swift', str(script)], check=True)
