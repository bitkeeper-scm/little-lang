# "make install" locations
PREFIX = /opt/little-lang
BINDIR := $(PREFIX)/bin
LGUI_OSX_INSTALL_DIR = /Applications  # for the OS X application bundle

MAJOR=1
MINOR=0
L_BUILD_ROOT = ./L
LGUI_BUILD_ROOT = ./Lgui
LIBPCRE = pcre/lib/libpcre.a

BKUSER	:= $(USER)
HERE    := $(shell pwd)
ROOT	:= $(HERE)
REPO    := $(shell basename $(HERE))
URL     := $(shell echo bk://work/$(ROOT) | sed s,/home/bk/,,)
LOG	:= $(shell echo LOG-$(BKUSER))
OSTYPE  := $(shell bash -c 'echo $$OSTYPE')

# platform-specific build options
PLATFORM = $(shell ./platform)
EXE=
ifeq "$(PLATFORM)" "win"
	S := win
	EXE=.exe
	TCLSH_NAME=tclsh.exe
	WISH_NAME=wish86.exe
	WISH=$(L_BUILD_ROOT)/$(BINDIR)/$(WISH_NAME)
	TCLSH_CONFIGURE_OPTS=--enable-shared
	TK_CONFIGURE_OPTS=--enable-shared
ifeq "$(shell ./msys_release)" "1.0.11"
	CFLAGS := -D_OLDMINGW
	export CFLAGS
endif
endif
ifeq "$(PLATFORM)" "macosx"
	S := unix
	TCLSH_NAME=tclsh
	WISH_NAME=wish8.6
	WISH=$(LGUI_BUILD_ROOT)/$(BINDIR)/$(WISH_NAME)
	TCLSH_CONFIGURE_OPTS=--enable-64bit --disable-shared
	TK_CONFIGURE_OPTS=--enable-64bit --enable-framework --enable-aqua
endif
ifeq "$(PLATFORM)" "unix"
	S := unix
	TCLSH_NAME=tclsh
	WISH_NAME=wish8.6
	WISH=$(L_BUILD_ROOT)/$(BINDIR)/$(WISH_NAME)
	TCLSH_CONFIGURE_OPTS=--enable-64bit --disable-shared
	TK_CONFIGURE_OPTS=--enable-64bit --disable-xss --enable-xft --disable-shared
endif
TCLSH=$(L_BUILD_ROOT)/$(BINDIR)/$(TCLSH_NAME)
L=$(L_BUILD_ROOT)/$(BINDIR)/L$(EXE)
L-gui=$(L_BUILD_ROOT)/$(BINDIR)/L-gui$(EXE)

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
	    $(MAKE) prefix=$(PREFIX) exec_prefix=$(PREFIX) libdir=$(PREFIX)/lib \
		INSTALL_ROOT=../../$(L_BUILD_ROOT) \
		install-binaries install-libraries
	mv $(TCLSH) $(L)

tk/$(S)/Makefile:
	cd tk/$(S) && \
	    ./configure --with-tcl=../../tcl/$(S) $(TK_CONFIGURE_OPTS)

$(WISH):
	$(MAKE) $(TCLSH)
	$(MAKE) tk/$(S)/Makefile
	cd tk/$(S) && \
	    $(MAKE) XLIBS=`pwd`/../../$(LIBPCRE) \
		prefix=$(PREFIX) exec_prefix=$(PREFIX) libdir=$(PREFIX)/lib \
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

doc: $(L)	## build little.html, some docs
	$(MAKE) INTERP=$(HERE)/$(L) -C tcl/doc/L little.html
	$(MAKE) -C tcl/doc/l-paper little.pdf
	mkdir -p $(L_BUILD_ROOT)/$(PREFIX)/doc
	-cp tcl/doc/L/little.html      $(L_BUILD_ROOT)/$(PREFIX)/doc
	-cp tcl/doc/l-paper/little.pdf $(L_BUILD_ROOT)/$(PREFIX)/doc

install: all ## install to $(PREFIX) (default /opt/little-lang)
	@$(MAKE) doc
	@test -d $(DESTDIR)$(PREFIX) || mkdir -p $(DESTDIR)$(PREFIX)
	@test -w $(DESTDIR)$(PREFIX) || { echo cannot write $(PREFIX); exit 1; }
	cp -pr $(L_BUILD_ROOT)/$(PREFIX)/* $(DESTDIR)$(PREFIX)
	if test "$(PLATFORM)" = "macosx"; then cp -pr $(LGUI_BUILD_ROOT)/tk/Lgui.app $(LGUI_OSX_INSTALL_DIR); fi

help:
	@grep -h -E '^[a-zA-Z_\ -]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "make %-20s %s\n", $$1, $$2}'
	@echo Suggested: make -j

src-tar: ## make source tarball
	@(DIR=little-lang-src-$(MAJOR).$(MINOR) ; \
	    TAR="$$DIR".tar.gz ; \
	    echo "Creating $$TAR ..." ; \
	    rm -rf "$$DIR" ; \
	    bk export -tplain -r+ "$$DIR" ; \
	    tar zcf "$$TAR" "$$DIR" ; \
	    rm -rf "$$DIR" ; \
	    echo Done ; \
	)

bin-tar: all ## make binary tarball
	@(ARCH=`./L/bin/L ./bin-version.l` ; \
	  DIR=little-lang-$(MAJOR).$(MINOR)-$$ARCH ; \
	    TAR="$$DIR".tar.gz ; \
	    echo "Creating $$TAR ..." ; \
	    rm -rf "$$DIR" ; \
	    mkdir "$$DIR" ; \
	    mv L Lgui "$$DIR" ; \
	    tar zcf "$$TAR" "$$DIR" ; \
	    rm -rf "$$DIR" ; \
	    echo Done ; \
	)

crankturn: crank.sh remote.sh  ## Run a clean-build + regressions in cluster
	REPO=$(REPO) URL=$(URL) REMOTE=remote.sh LOG=$(LOG) bash crank.sh

.PHONY: unix macosx win src-tar bin-tar crankturn
