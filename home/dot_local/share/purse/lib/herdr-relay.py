"""herdr-relay — the container half of herdr-bridge.

Runs inside a devcontainer, listens on a unix socket, and forwards each
connection to the host's `herdr-bridge` daemon over TCP with the shared token
in front of it. `dcbridge` pushes this file in and supervises it, the way it
does `dbr container-daemon`.

The unix socket exists because that is the only thing herdr's agent
integration hooks know how to open: they connect to $HERDR_SOCKET_PATH with
AF_UNIX and give up quietly on anything else. `dcsh` points that variable here.

Invoked as `python3 herdr-relay.py --socket ... --token-file ...`; no shebang,
because dcbridge stamps a fingerprint line on top of it.
"""

import argparse
import os
import socket
import sys
import threading

HANDSHAKE = "HERDR-BRIDGE/1"
DEFAULT_PORT = 19287


def resolve_host(explicit):
    """Find the host, in the order dbr's container daemon uses.

    Kept identical on purpose: a container where one of these bridges works and
    the other does not is a confusing thing to debug.
    """
    if explicit:
        return explicit
    from_env = os.environ.get("DCBRIDGE_HOST")
    if from_env:
        return from_env
    try:
        socket.getaddrinfo("host.docker.internal", None)
        return "host.docker.internal"
    except OSError:
        return "127.0.0.1"


def pump(src, dst):
    try:
        while True:
            chunk = src.recv(65536)
            if not chunk:
                break
            dst.sendall(chunk)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def serve(conn, host, port, token):
    upstream = None
    try:
        upstream = socket.create_connection((host, port), timeout=5)
        upstream.sendall(f"{HANDSHAKE} {token}\n".encode())
        reply = b""
        while b"\n" not in reply:
            chunk = upstream.recv(64)
            if not chunk:
                return
            reply += chunk
        greeting, _, spill = reply.partition(b"\n")
        if greeting.strip() != b"OK":
            print(f"herdr-relay: host refused: {greeting!r}", flush=True)
            return
        upstream.settimeout(None)
        # The host may have coalesced its OK with the first response bytes.
        if spill:
            conn.sendall(spill)
        threading.Thread(target=pump, args=(conn, upstream), daemon=True).start()
        pump(upstream, conn)
    except OSError as error:
        print(f"herdr-relay: {error}", flush=True)
    finally:
        for sock in (conn, upstream):
            if sock is not None:
                try:
                    sock.close()
                except OSError:
                    pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--host")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()

    try:
        token = open(args.token_file).read().strip()
    except OSError as error:
        print(f"herdr-relay: no token: {error}", file=sys.stderr)
        return 1
    if not token:
        print("herdr-relay: empty token", file=sys.stderr)
        return 1

    host = resolve_host(args.host)

    # Unlink first: a container restarted without clearing /dev/shm leaves the
    # old socket file behind, and bind() would fail on it forever.
    try:
        os.unlink(args.socket)
    except FileNotFoundError:
        pass
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    old_umask = os.umask(0o177)
    try:
        listener.bind(args.socket)
    finally:
        os.umask(old_umask)
    listener.listen(16)

    print(f"herdr-relay: {args.socket} -> {host}:{args.port}", flush=True)
    while True:
        conn, _ = listener.accept()
        threading.Thread(
            target=serve, args=(conn, host, args.port, token), daemon=True
        ).start()


if __name__ == "__main__":
    sys.exit(main())
