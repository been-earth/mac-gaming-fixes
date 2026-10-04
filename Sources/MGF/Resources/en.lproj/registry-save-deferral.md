# registry save deferral

wine freezes every process in a bottle for about a quarter of a second, twice a minute, to rewrite its registry. this fix holds that write back while a game is running.

## symptom

every 30 s the game hitches. the network graph shows 15–17 ticks arriving in one burst. it happens on loopback too, so wi-fi is not involved.

## cause

wineserver is single-threaded. every 30 s it rewrites each registry branch that changed since the last save, as one text file, on that one thread. in a steam bottle `system.reg` is about 12 mb (36.5k keys), so one save blocks every server call and socket event for ~240 ms.

the branch is never clean for long: steam touches `HKLM\Software\Wow6432Node\Valve\SteamService` once a minute.

## measurement

a 64 hz udp echo on loopback, received inside the game bottle the way valve's networking code receives (`WSAEventSelect` + `recvfrom`). deadlock running, 110–120 s per run.

| receiver | p99 | max | late > 5 ms |
|---|---|---|---|
| native | 1.2 ms | 8 ms | 2 / 7040 |
| wine, stock | 6.1 ms | 264 ms | 80 / 7040 |
| wine, fixed | 3.1 ms | 10 ms | 18 / 7680 |

```bars
longest stall | ms | 264 | 10
```

the four stock stalls were 232–264 ms long, exactly 30 s apart, and each ended within 7 ms of `system.reg` being rewritten.

## the fix

a small library is injected into wineserver and interposes `open()`. when the periodic save of a branch larger than 1 mb begins while the server is busy (its own cpu share above 5 %), the temp-file open fails fast. the branch stays dirty, wineserver retries 30 s later, and the save goes through once the bottle is quiet. saves on exit and of small branches such as `user.reg` are untouched.

```c wineserver_fix.c
if (branch[0] && periodic) {
    double share = cpu_share();
    if (busy_cpu > 0 && share > busy_cpu) {  // a game is running
        errno = EACCES;                      // save_branch() gives up, branch stays dirty
        return -1;
    }
}
return open(path, flags, mode);
```

## what changes on disk

- `bin/wineserver` becomes a 5-line wrapper script
- `bin/wineserver.orig` is the untouched original
- `bin/wineserver.real` is an unsigned copy: the signed binary has the hardened runtime and ignores `DYLD_INSERT_LIBRARIES`
- `bin/wineserver_fix.dylib` is the injected library

## verify

play for a few minutes, then read the log. a game session shows one `defer system.reg` line every 30 s.

```sh
tail -f ~/Library/Logs/mgf/regsave.log
```

## limits

- a light game can stay under the 5 % threshold and keep its stalls. lower `busy threshold` in settings and check the log.
- if wineserver is killed instead of exiting, registry changes made while the game ran are lost. a normal quit saves them.
- a crossover update or a cxpatcher re-patch removes the wrapper. the app applies it again when `re-apply fixes` is on.
