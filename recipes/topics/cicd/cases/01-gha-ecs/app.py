import http.server, os, socketserver
VERSION = os.environ.get("APP_VERSION", "v1")
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"lab-gha {VERSION}\n".encode()
        self.send_response(200); self.send_header("Content-Type","text/plain")
        self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): print(self.address_string(), *a)
print(f"lab-gha starting {VERSION}", flush=True)
socketserver.TCPServer(("",8080), H).serve_forever()
