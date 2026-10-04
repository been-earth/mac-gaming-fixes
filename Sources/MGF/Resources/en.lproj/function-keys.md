# function keys

games bind f1–f12. a macbook sends brightness and media keys instead unless fn is held. this switch flips the top row at once, by hand or when a game starts.

## what it does

the same switch as system settings → keyboard → keyboard shortcuts → function keys, without opening settings and without logging out.

## how it works

the setting lives in the global defaults domain. writing it does nothing until the system re-reads its settings, which a helper inside macos does on request.

```sh fkeys.sh
defaults write -g com.apple.keyboard.fnState -bool true
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
```

the keyboard driver follows at once: its `HIDFKeyMode` property flips between 0 and 1.

```sh
ioreg -l -w0 | grep -o '"HIDFKeyMode"=[0-9]' | sort -u
```

## triggers

apps: the row turns on while any chosen process is running and back off when the last one exits. the list of processes is read every 2 s. wine games appear under their `.exe` name, taken from the first argument of the process.

game mode: the row follows macos game mode. there is no public api for it. the system publishes the state as the darwin notification `com.apple.system.game_mode_status_changed`, which the app listens to.

> [!WARNING]
> wine games do not always trigger game mode: crossover's loader is not marked as a game. add the game under apps to be sure.

a trigger only turns off what it turned on. if the row was already on, or you flip the switch by hand while the game runs, it stays as you left it.

## limits

- triggers work only while the app is running. closing the window quits it.
- `activateSettings` is a private helper and the game mode notification is undocumented. both worked on macos 27.0. a future release may change them.
- with the row on, brightness and volume need fn.
- not checked on third-party keyboards.
