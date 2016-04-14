# "make install" locations
PREFIX = /usr/local
LGUI_OSX_INSTALL_DIR = /Applications  # for the OS X application bundle

MAJOR=1
MINOR=0
L_BUILD_ROOT = ./L
LGUI_BUILD_ROOT = ./Lgui
LIBPCRE = pcre/lib/libpcre.a

# platform-specific build options
PLATFORM = $(shell ./platform)
EXE=
ifeq "$(PLATFORM)" "win"
	S := win
	EXE=.exe
	TCLSH_NAME=tclsh.exe
	WISH_NAME=wish86.exe
	WISH=$(L_BUILD_ROOT)/bin/$(WISH_NAME)
	TCLSH_CONFIGURE_OPTS=--enable-shared
	TK_CONFIGURE_OPTS=--enable-shared
endif
ifeq "$(PLATFORM)" "macosx"
	S := unix
	TCLSH_NAME=tclsh
	WISH_NAME=wish8.6
	WISH=$(LGUI_BUILD_ROOT)/bin/$(WISH_NAME)
	TCLSH_CONFIGURE_OPTS=--enable-64bit --disable-shared
	TK_CONFIGURE_OPTS=--enable-64bit --enable-framework --enable-aqua
endif
ifeq "$(PLATFORM)" "unix"
	S := unix
	TCLSH_NAME=tclsh
	WISH_NAME=wish8.6
	WISH=$(L_BUILD_ROOT)/bin/$(WISH_NAME)
	TCLSH_CONFIGURE_OPTS=--enable-64bit --disable-shared
	TK_CONFIGURE_OPTS=--enable-64bit --disable-xss --enable-xft --disable-shared
endif
TCLSH=$(L_BUILD_ROOT)/bin/$(TCLSH_NAME)
L=$(L_BUILD_ROOT)/bin/L$(EXE)
l=$(L_BUILD_ROOT)/bin/l$(EXE)
L-gui=$(L_BUILD_ROOT)/bin/L-gui$(EXE)
l-gui=$(L_BUILD_ROOT)/bin/l-gui$(EXE)

all: ## default, build for `./platform`
	$(MAKE) $(PLATFORM)

unix win: ## build for unix or windows
	$(MAKE) $(TCLSH)
	$(MAKE) $(WISH)

macosx: ## build for macos
	$(MAKE) $(TCLSH)
	$(MAKE) $(LGUI_BUILD_ROOT)/tk/Wish.app

tcl/$(S)/Makefile:
	cd tcl/$(S) && \
	    ./configure --enable-pcre=default --with-pcre=../../pcre \
		$(TCLSH_CONFIGURE_OPTS)

$(TCLSH):
	$(MAKE) $(LIBPCRE)
	$(MAKE) tcl/$(S)/Makefile
	echo "proc Lver {} { return \"$(MAJOR).$(MINOR)\" }" >tcl/library/Lver.tcl
	cd tcl/$(S) && \
	    $(MAKE) prefix= exec_prefix= INSTALL_ROOT=../../$(L_BUILD_ROOT) \
		install-binaries install-libraries
	mv $(TCLSH) $(L)

tk/$(S)/Makefile:
	cd tk/$(S) && \
	    ./configure --with-tcl=../../tcl/$(S) $(TK_CONFIGURE_OPTS)

$(WISH):
	$(MAKE) $(TCLSH)
	$(MAKE) tk/$(S)/Makefile
	cd tk/$(S) && \
	    $(MAKE) XLIBS=`pwd`/../../$(LIBPCRE) prefix= exec_prefix= \
		INSTALL_ROOT=../../$(L_BUILD_ROOT) \
		install-binaries install-libraries; \
	pwd
	mv $(WISH) $(L-gui)

$(LGUI_BUILD_ROOT)/tk/Wish.app:
	$(MAKE) $(TCLSH)
	$(MAKE) tk/$(S)/Makefile
	rm -rf $(LGUI_BUILD_ROOT)
	(cd tcl/macosx && \
	    $(MAKE) EXTRA_CONFIGURE_ARGS="--enable-pcre=default --with-pcre=`pwd`/../../pcre" \
		embedded)
	(cd tk/macosx && \
	    $(MAKE) XLIBS="../../../$(LIBPCRE)" \
		EXTRA_CONFIGURE_ARGS="--enable-aqua" embedded)
	(cd build/tk; \
	mv Wish.app Lgui.app; \
	ln -s Lgui.app Wish.app; \
	rm -f "Wish Shell.app" wish*; \
	ln -sf Lgui.app/Contents/MacOS/Lgui Lgui; \
	cd Lgui.app/Contents; \
	sed "s/>Wish</>Lgui</g; s/>WiSH</>Lgui</" Info.plist >NewInfo.plist; \
	mv NewInfo.plist Info.plist; \
	cd MacOS; \
	mv Wish Lgui; \
	cd ../../../../..)
	mv build $(LGUI_BUILD_ROOT)

$(LIBPCRE): pcre/Makefile
	cd pcre && $(MAKE) && $(MAKE) install

pcre/Makefile:
	cd pcre && ./configure --disable-cpp --disable-shared --enable-utf8=yes --prefix=`pwd`

test test-l: $(TCLSH)
	$(MAKE) -C tcl/$(S) test-l

clean: ## clean up after a build
	-test -f pcre/Makefile && { \
		echo === clean pcre ===; \
		$(MAKE) -C pcre distclean; \
		cd pcre && rm -rf bin include lib share; \
	}
	-test -f tcl/$(S)/Makefile && { \
		echo === clean tcl ===; \
		$(MAKE) -C tcl/$(S) distclean; \
		cd tcl/doc/L && make clean; \
	}
	-test -f tk/$(S)/Makefile && { \
		echo === clean tk ===; \
		$(MAKE) -C tk/$(S) distclean; \
	}
	rm -rf $(L_BUILD_ROOT) $(LGUI_BUILD_ROOT) build

clobber: ## really clean up, assumes BK, cleans everything
	@$(MAKE) clean
	rm -rf L

doc: $(L_BUILD_ROOT)/bin/tclsh ## build little.html, some docs
	$(MAKE) -C tcl/doc/L little.html
	-test -d L/doc/L || mkdir -p L/doc/L
	cp tcl/doc/L/little.html L/doc/L
	$(MAKE) -C tcl/doc/l-paper little.pdf
	cp tcl/doc/l-paper/little.pdf L/doc/L

install: all ## install to $(PREFIX) (default /usr/local)
	@$(MAKE) doc
	@test -d $(PREFIX) || mkdir $(PREFIX)
	@test -w $(PREFIX) || { echo cannot write $(PREFIX); exit 1; }
	cp -pr $(L_BUILD_ROOT)/* $(PREFIX)
	-test "$(PLATFORM)" = "macosx" && cp -pr $(LGUI_BUILD_ROOT)/tk/Lgui.app $(LGUI_OSX_INSTALL_DIR)

help:
	@grep -h -E '^[a-zA-Z_\-\ ]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "make %-20s %s\n", $$1, $$2}'
	@echo Suggested: make -j

.PHONY: unix macosx win
