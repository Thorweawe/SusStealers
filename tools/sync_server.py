"""Studio ile dosyalar arasinda iki yonlu kopru.

GET  /src/...  -> dosyayi dondurur  (Studio kodu ceker)
POST /src/...  -> govdeyi dosyaya yazar (Studio kodu geri gonderir)

Calistirmak icin proje kokunde:
    python tools/sync_server.py

Studio tarafi icin README'deki run_code orneklerine bak.
"""

import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))
PORT = 8788

# Sadece bu klasorlerin altina yazilabilir. Kazayla baska yere
# yazmayi engellemek icin; sunucu yerelde acik duruyor.
WRITABLE = ("src",)


def resolve(url_path):
    """URL yolunu proje icindeki gercek yola cevirir. Disari cikarsa None."""
    relative = url_path.lstrip("/")
    full = os.path.abspath(os.path.join(ROOT, relative))
    if not full.startswith(ROOT + os.sep):
        return None
    return full


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))

    def _send(self, code, body=b"", content_type="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = resolve(self.path.split("?", 1)[0])
        if not path or not os.path.isfile(path):
            self._send(404, b"yok")
            return
        with open(path, "rb") as f:
            self._send(200, f.read())

    def do_POST(self):
        clean = self.path.split("?", 1)[0]
        relative = clean.lstrip("/")

        if not relative.startswith(WRITABLE):
            self._send(403, b"bu yola yazilamaz")
            return

        path = resolve(clean)
        if not path:
            self._send(403, b"proje disi yol")
            return

        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)

        os.makedirs(os.path.dirname(path), exist_ok=True)
        # Studio CRLF gonderebilir; depoda LF tutuyoruz.
        text = body.decode("utf-8").replace("\r\n", "\n")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)

        print("  YAZILDI %s (%d bayt)" % (relative, len(text)))
        self._send(200, str(len(text)).encode())


if __name__ == "__main__":
    print("Kok    : %s" % ROOT)
    print("Adres  : http://127.0.0.1:%d/" % PORT)
    print("GET  -> dosya oku | POST -> dosyaya yaz (sadece src/ altina)")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
