# low-latency wi-fi

the mac's wi-fi chip may hold packets for up to 25 ms to save power. it stops when a socket asks for real-time service. wine never asks, so this fix asks for it.

## symptom

on wi-fi, a quarter to half of the game's packets arrive 10–25 ms late even one hop from the router. the slow mode comes and goes on a scale of tens of seconds.

## cause

the chip's power saving holds traffic up to a hard ceiling of ~25 ms unless some socket on the interface carries a real-time service class (`SO_NET_SERVICE_TYPE`). the ceiling is the same from 16 to 256 packets per second. the effect is interface-wide: one tagged socket speeds up every flow.

## measurement

a 64 hz udp flow to the router, on ac power, 5 ghz, six alternating rounds per class.

| service class | median | late > 15 ms |
|---|---|---|
| best effort | 8.7 ms | 25 % |
| responsive data | 10.7 ms | 17 % |
| interactive video | 3.8 ms | 1.2 % |
| voice | 3.8 ms | 4.4 % |

```bars
median to router | ms | 8.7 | 3.8
```

the same probe from a winsock socket inside a test bottle: stock 10.5–14.4 ms median with 20–45 % late, fixed 4.0–4.4 ms with 0–10 %.

## the fix

wine creates every windows socket inside wineserver, so one hook covers all games in the bottle. the injected library interposes `socket()` and tags each udp socket as interactive video.

```c wineserver_fix.c
static int my_socket(int domain, int type, int protocol) {
    int fd = socket(domain, type, protocol);
    if (fd >= 0 && udp_service && type == SOCK_DGRAM)
        setsockopt(fd, SOL_SOCKET, SO_NET_SERVICE_TYPE,
                   &udp_service, sizeof udp_service);
    return fd;
}
```

## what changes on disk

- the same wrapper and library as registry save deferral: `bin/wineserver`, `bin/wineserver.real`, `bin/wineserver_fix.dylib`
- with both network fixes off, the original `bin/wineserver` is put back and the rest is removed

## limits

- fixes the hold-off only. packet loss at the isp and bufferbloat on the router are untouched.
- on battery the same link measured p99 118 ms against 25 ms on ac. play plugged in.
- whether native games set the class themselves was not checked.
- `udp service class` in settings switches between interactive video and voice.
