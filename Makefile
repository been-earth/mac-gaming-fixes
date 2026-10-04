# MacGamingFixes. `make build` makes build/MacGamingFixes.app, `make dmg` wraps it into the installer,
# `make test` runs every check.
PAYLOAD := Sources/MGF/Resources/Payload
# CrossOver's Wine is x86_64 (it runs under Rosetta), so both libraries are too.
CC_PAYLOAD := clang -arch x86_64 -O2 -mmacosx-version-min=10.15 -dynamiclib

.PHONY: payload build dmg run test site clean

payload: $(PAYLOAD)/wineserver_fix.dylib $(PAYLOAD)/winecoreaudio.so

$(PAYLOAD)/wineserver_fix.dylib: native/wineserver_fix.c
	mkdir -p $(PAYLOAD)
	$(CC_PAYLOAD) $< -o $@

# The wrapper re-exports whatever sits next to it as winecoreaudio_real.so. At link time that is an
# empty stub with that install name; on the user's machine it is a copy of the real driver, so
# installing needs no developer tools.
$(PAYLOAD)/winecoreaudio.so: native/coreaudio_iobuf.c
	mkdir -p build/stub $(PAYLOAD)
	$(CC_PAYLOAD) -x c /dev/null -install_name @loader_path/winecoreaudio_real.so -o build/stub/winecoreaudio_real.so
	$(CC_PAYLOAD) $< -framework CoreAudio -Wl,-reexport_library,build/stub/winecoreaudio_real.so -o $@

build: payload
	swift build -c release
	scripts/bundle.sh

# build/MacGamingFixes-<version>.dmg
dmg: build
	scripts/dmg.sh

run: build
	open build/MacGamingFixes.app

test: payload
	swift test
	scripts/check-strings.py

# docs/ is the GitHub Pages site: the landing pages, the articles as HTML, the social preview image.
site:
	scripts/site.py

clean:
	rm -rf .build build $(PAYLOAD)/*.dylib $(PAYLOAD)/*.so
