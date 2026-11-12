#!/usr/bin/env python3
"""One explicit nonpersonal public read. Independent Python probe, NEVER an app transport fallback."""
import datetime, hashlib, http.client, ipaddress, json, socket, ssl
host = "example.com"
records = socket.getaddrinfo(host,443,socket.AF_INET,socket.SOCK_STREAM)
addresses = sorted({record[4][0] for record in records})
if not addresses or not all(ipaddress.ip_address(ip).is_global for ip in addresses):
    raise RuntimeError("Refusing nonpublic DNS result")
# A vetted IP is the actual socket destination; the original hostname remains the TLS identity.
with socket.create_connection((addresses[0],443),timeout=10) as raw:
    with ssl.create_default_context().wrap_socket(raw,server_hostname=host) as connection:
        connection.sendall(b"GET / HTTP/1.1\r\nHost: example.com\r\nUser-Agent: Jarvis-EVO-Engineering-Verification/1.0\r\nAccept: text/html\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n")
        response = http.client.HTTPResponse(connection)
        response.begin()
        if response.status != 200 or response.getheader("Content-Encoding", "identity") != "identity":
            raise RuntimeError("Unsupported response; no retry or redirect followed")
        body = response.read(262145)
        if len(body) > 262144: raise RuntimeError("Body exceeds bound")
        report = {"time_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"url":"https://example.com/",
                  "selected_literal":addresses[0],"peer":connection.getpeername()[0],"tls_version":connection.version(),
                  "hostname_certificate_verification":True,"http_status":response.status,"body_bytes":len(body),
                  "body_sha256":hashlib.sha256(body).hexdigest(),"native_apple_execution":False}
        print(json.dumps(report,indent=2))
