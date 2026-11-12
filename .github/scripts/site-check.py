#!/usr/bin/env python3
"""Check the website in docs/ (served by GitHub Pages next to the apt repo).

Usage: site-check.py <docs-dir>

Every page must carry a Content-Security-Policy <meta> that allows nothing
beyond the site itself (no scripts at all), load nothing from another site,
and link only to files that exist. sitemap.xml, robots.txt, security.txt and
CNAME must agree with each other and with the domain.

Standard library only; exits 1 and lists every problem it finds.
"""
import datetime
import pathlib
import re
import sys
from html.parser import HTMLParser

DOMAIN = "pwsh-termux.machlev.org"
SITE = f"https://{DOMAIN}"

# Paths the apt repository adds when the site is deployed (see assemble-site.sh);
# they do not exist under docs/ but are linked from the pages.
GENERATED = ("/pwsh-termux.gpg", "/pwsh-termux.asc", "/pwsh-termux-keyring.deb", "/dists/", "/pool/")

# Directives every page's policy must contain, exactly.
REQUIRED_CSP = ("default-src 'none'", "base-uri 'none'", "form-action 'none'")
FORBIDDEN_TAGS = {"script", "form", "base", "iframe", "object", "embed"}


class Page(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.csp = []
        self.refs = []          # (tag, attr, value) of everything that loads or links
        self.problems = []
        self.h1 = 0
        self.lang = None
        self.title = False
        self.viewport = False
        self.main_id = False
        self.skip_link = False
        self.has_title_text = False
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.tags.append(tag)
        if tag in FORBIDDEN_TAGS:
            self.problems.append(f"<{tag}> is not allowed")
        for name in a:
            if name.startswith("on"):
                self.problems.append(f"inline event handler {name}= on <{tag}>")
        if tag == "html":
            self.lang = a.get("lang")
        elif tag == "title":
            self.title = True
            self._in_title = True
        elif tag == "h1":
            self.h1 += 1
        elif tag == "meta":
            if (a.get("http-equiv") or "").lower() == "content-security-policy":
                self.csp.append(a.get("content") or "")
            if a.get("name") == "viewport":
                self.viewport = True
        elif tag == "main" and a.get("id") == "main":
            self.main_id = True
        elif tag == "img" and "alt" not in a:
            self.problems.append("<img> without an alt attribute")
        if tag == "a":
            if a.get("href") == "#main":
                self.skip_link = True
            if "href" in a:
                self.refs.append(("a", "href", a["href"]))
        elif tag == "link" and "href" in a:
            rel = (a.get("rel") or "").lower().split()
            if "canonical" in rel or "alternate" in rel:
                # metadata, not a load: it may name the site's own absolute URL
                if not a["href"].startswith(SITE + "/"):
                    self.problems.append(f"<link rel={' '.join(rel)}> must point to {SITE}/: {a['href']}")
            else:
                self.refs.append(("link", "href", a["href"]))
        for attr in ("src", "srcset", "poster", "data"):
            if attr in a and tag not in ("a",):
                self.refs.append((tag, attr, a[attr]))

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title and data.strip():
            self.has_title_text = True


def local_target(docs: pathlib.Path, page: pathlib.Path, ref: str):
    """Return the file a local reference points to, or None if it is not local."""
    ref = ref.split("#", 1)[0].split("?", 1)[0]
    if ref == "" or re.match(r"^[a-z][a-z0-9+.-]*:", ref, re.I) or ref.startswith("//"):
        return None
    if ref.startswith("/"):
        if any(ref == g or ref.startswith(g) for g in GENERATED):
            return "generated"
        target = docs / ref.lstrip("/")
    else:
        target = page.parent / ref
    if target.is_dir() or ref.endswith("/"):
        target = target / "index.html"
    return target


def check_page(docs: pathlib.Path, page: pathlib.Path, errors: list):
    name = page.relative_to(docs)
    p = Page()
    p.feed(page.read_text(encoding="utf-8"))
    problems = [f"{name}: {x}" for x in p.problems]

    if len(p.csp) != 1:
        problems.append(f"{name}: needs exactly one Content-Security-Policy <meta> (found {len(p.csp)})")
    else:
        csp = p.csp[0]
        for directive in REQUIRED_CSP:
            if directive not in csp:
                problems.append(f"{name}: CSP lacks {directive!r}")
        if "script-src" in csp or "'unsafe" in csp:
            problems.append(f"{name}: CSP must not allow scripts or 'unsafe-*'")
        if re.search(r"https?:|\*", csp):
            problems.append(f"{name}: CSP must not allow another origin")
    if not p.lang:
        problems.append(f"{name}: <html> needs a lang attribute")
    if not (p.title and p.has_title_text):
        problems.append(f"{name}: needs a non-empty <title>")
    if not p.viewport:
        problems.append(f"{name}: needs a viewport <meta>")
    if p.h1 != 1:
        problems.append(f"{name}: needs exactly one <h1> (found {p.h1})")
    if not p.main_id:
        problems.append(f"{name}: needs <main id=\"main\">")
    if not p.skip_link:
        problems.append(f"{name}: needs a skip link (href=\"#main\")")

    for tag, attr, value in p.refs:
        for ref in re.split(r",\s*", value) if attr == "srcset" else [value]:
            ref = ref.strip().split(" ")[0]
            if tag == "a":
                if ref.startswith("http://"):
                    problems.append(f"{name}: plain-http link {ref}")
                if ref.startswith("//"):
                    problems.append(f"{name}: protocol-relative link {ref}")
                if ref.startswith("#"):
                    continue
            elif re.match(r"^([a-z]+:)?//", ref, re.I):
                problems.append(f"{name}: <{tag} {attr}> loads from another site: {ref}")
                continue
            target = local_target(docs, page, ref)
            if target is None or target == "generated":
                continue
            if not target.exists():
                problems.append(f"{name}: <{tag} {attr}> points to a missing file: {ref}")
    errors.extend(problems)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    docs = pathlib.Path(sys.argv[1])
    errors = []

    cname = docs / "CNAME"
    if not cname.is_file() or cname.read_text().strip() != DOMAIN:
        errors.append(f"CNAME must contain exactly {DOMAIN}")

    pages = sorted(docs.glob("*.html"))
    if not (docs / "index.html").is_file():
        errors.append("index.html is missing")
    for page in pages:
        check_page(docs, page, errors)

    sitemap = docs / "sitemap.xml"
    if sitemap.is_file():
        listed = set(re.findall(r"<loc>([^<]+)</loc>", sitemap.read_text()))
        expected = {SITE + "/" if p.name == "index.html" else f"{SITE}/{p.name}"
                    for p in pages if p.name != "404.html"}
        for missing in sorted(expected - listed):
            errors.append(f"sitemap.xml does not list {missing}")
        for extra in sorted(listed - expected):
            errors.append(f"sitemap.xml lists {extra}, which is not a page")
    else:
        errors.append("sitemap.xml is missing")

    robots = docs / "robots.txt"
    if not robots.is_file() or f"Sitemap: {SITE}/sitemap.xml" not in robots.read_text():
        errors.append(f"robots.txt must point to {SITE}/sitemap.xml")

    sec = docs / ".well-known" / "security.txt"
    if sec.is_file():
        text = sec.read_text()
        if f"Canonical: {SITE}/.well-known/security.txt" not in text:
            errors.append("security.txt: Canonical must be the site's own URL")
        if "Contact:" not in text:
            errors.append("security.txt: Contact is missing")
        m = re.search(r"^Expires:\s*(\S+)", text, re.M)
        if not m:
            errors.append("security.txt: Expires is missing")
        else:
            expires = datetime.datetime.fromisoformat(m.group(1).replace("Z", "+00:00"))
            left = expires - datetime.datetime.now(datetime.timezone.utc)
            if left < datetime.timedelta(days=30):
                errors.append(f"security.txt expires in {left.days} days: renew Expires (RFC 9116)")
    else:
        errors.append(".well-known/security.txt is missing")

    for needed in ("style.css", "favicon.svg", "llms.txt", ".nojekyll"):
        if not (docs / needed).is_file():
            errors.append(f"{needed} is missing")

    if errors:
        print("Site check failed:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print(f"Site check passed: {len(pages)} pages, CSP and links OK.")


if __name__ == "__main__":
    main()
