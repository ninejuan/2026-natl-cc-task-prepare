#!/usr/bin/env python3
"""ActiveMQ(Amazon MQ) STOMP over TLS 클라이언트 — 외부 라이브러리 없이 표준 라이브러리만.

  python3 stomp_client.py <broker-host> <user> <password> [queue]

`stomp.py` 9.x 는 macOS 에서 `'PollableQueue ... is not registered'` 로 죽는 경우가 있어서
STOMP 1.2 프레임을 직접 만든다. 대회 PC 에 pip 설치가 막혀도 이건 그냥 돈다.

★ Amazon MQ ActiveMQ 는 퍼블릭이어도 VPC 보안그룹을 타므로 61614(STOMP+SSL) 인바운드를 열어야 한다.
"""
import json, socket, ssl, sys, time

NUL = b"\x00"


def frame(cmd: str, headers: dict, body: bytes = b"") -> bytes:
    h = "".join(f"{k}:{v}\n" for k, v in headers.items())
    return f"{cmd}\n{h}\n".encode() + body + NUL


def main():
    host, user, pw = sys.argv[1], sys.argv[2], sys.argv[3]
    queue = sys.argv[4] if len(sys.argv) > 4 else "lab-aq"

    s = ssl.create_default_context().wrap_socket(
        socket.create_connection((host, 61614), timeout=20), server_hostname=host)
    s.settimeout(20)

    s.sendall(frame("CONNECT", {"accept-version": "1.2", "host": "/", "login": user, "passcode": pw}))
    assert s.recv(4096).split(b"\n")[0] == b"CONNECTED", "STOMP 연결 실패"
    print("CONNECTED")

    for i in range(5):
        b = json.dumps({"id": i, "msg": "hello-activemq"}).encode()
        s.sendall(frame("SEND", {"destination": f"/queue/{queue}", "content-length": str(len(b)),
                                 "content-type": "application/json", "persistent": "true"}, b))
    print("published 5")

    s.sendall(frame("SUBSCRIBE", {"id": "sub-1", "destination": f"/queue/{queue}", "ack": "auto"}))
    buf, got, t0 = b"", [], time.time()
    while len(got) < 5 and time.time() - t0 < 25:
        try:
            d = s.recv(8192)
        except socket.timeout:
            break
        if not d:
            break
        buf += d
        while NUL in buf:
            f, buf = buf.split(NUL, 1)
            f = f.lstrip(b"\n")
            if not f:
                continue
            head, _, body = f.partition(b"\n\n")
            if head.split(b"\n")[0] == b"MESSAGE":
                got.append(body.decode())
    print("consumed:", got)
    assert len(got) == 5, f"소비 {len(got)}/5"

    s.sendall(frame("DISCONNECT", {"receipt": "bye"}))
    s.close()


if __name__ == "__main__":
    main()
