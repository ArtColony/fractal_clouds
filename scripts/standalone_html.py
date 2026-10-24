#!/usr/bin/env python3
"""Make docs/techniques.html a single file that needs no checkout.

    python3 -I scripts/standalone_html.py SRC_ROOT OUT.html [LINK_BASE]

SRC_ROOT is a tree laid out like the repo (it holds docs/techniques.html and
the images it points at, which sit in docs/, docs/techniques/ and
gallery/previews/). Every relative <img src> is replaced by a data: URI, and
the link to settings.md by LINK_BASE/settings.md (a URL, such as the file at a
release tag on GitHub) when LINK_BASE is given. Fails if an image is missing
or, with LINK_BASE, a relative reference is left over.
"""
import base64, mimetypes, os, re, sys

root, out = os.path.realpath(sys.argv[1]), sys.argv[2]
link_base = sys.argv[3] if len(sys.argv) > 3 else None
docs = os.path.join(root, "docs")
html = open(os.path.join(docs, "techniques.html"), encoding="utf-8").read()


def inline(m):
    ref = m.group(2)
    if re.match(r"(data:|https?:|#)", ref):
        return m.group(0)
    path = os.path.realpath(os.path.join(docs, ref))
    if not path.startswith(root + os.sep):
        sys.exit("standalone_html: %s points outside the tree" % ref)
    if not os.path.isfile(path):
        sys.exit("standalone_html: missing image %s" % ref)
    mime = {".svg": "image/svg+xml"}.get(os.path.splitext(path)[1]) or mimetypes.guess_type(path)[0]
    if not mime:
        sys.exit("standalone_html: unknown image type for %s" % ref)
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return '%ssrc="data:%s;base64,%s"' % (m.group(1), mime, data)


html = re.sub(r'(<img\b[^>]*?\s)src="([^"]*)"', inline, html)
if link_base:
    html = html.replace('href="settings.md"', 'href="%s/settings.md"' % link_base.rstrip("/"))
left = re.findall(r'(?:src|href)="(?!data:|https?:|#)([^"]*)"', html)
if left and link_base:
    sys.exit("standalone_html: relative references left: %s" % ", ".join(sorted(set(left))))
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
with open(out, "w", encoding="utf-8") as f:
    f.write(html)
print("standalone_html: %s (%.1f MB)" % (out, len(html) / 1e6))
