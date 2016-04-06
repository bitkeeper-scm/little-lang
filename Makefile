# "make install" locations
PREFIX = /usr/local
LGUI_OSX_INSTALL_DIR = /Applications  # for the OS X application bundle

L_BUILD_ROOT = ./L
LGUI_BUILD_ROOT = ./Lgui
LIBPCRE = pcre/lib/libpcre.a

# Where we build the git repos
GIT=BitKeeper/tmp/git

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
	cd tcl/$(S) && \
	    $(MAKE) prefix= exec_prefix= INSTALL_ROOT=../../$(L_BUILD_ROOT) \
		install-binaries install-libraries
	cp $(TCLSH) $(L)
	cp $(L) $(l)

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
	cp $(WISH) $(L-gui)
	cp $(L-gui) $(l-gui)

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

doc: $(L_BUILD_ROOT)/bin/tclsh ## build L.html, some docs
	$(MAKE) -C tcl/doc/L L.html
	-test -d L/doc/L || mkdir -p L/doc/L
	cp tcl/doc/L/L.html L/doc/L

install: all ## install to $(PREFIX) (default /usr/local)
	@$(MAKE) doc
	@test -d $(PREFIX) || mkdir $(PREFIX)
	@test -w $(PREFIX) || { echo cannot write $(PREFIX); exit 1; }
	cp -pr $(L_BUILD_ROOT)/* $(PREFIX)
	-test "$(PLATFORM)" = "macosx" && cp -pr $(LGUI_BUILD_ROOT)/tk/Lgui.app $(LGUI_OSX_INSTALL_DIR)

help:
	@grep -h -E '^[a-zA-Z_\-\ ]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "make %-20s %s\n", $$1, $$2}'
	@echo Suggested: make -j

git: ## export the nested collection as a git repo with submodules
	rm -rf $(GIT)
	for repo in `bk comps`; \
	do	repo=`basename $$repo` ; \
		git init -q $(GIT)/$$repo.git; \
		(cd $(GIT)/$$repo.git && git remote add origin git@github.com:bitkeeper-scm/$$repo.git) ; \
		bk --cd=$$repo fast-export -S | \
			(cd $(GIT)/$$repo.git && git fast-import --quiet); \
		(cd $(GIT)/$$repo.git && git checkout -f master) ; \
		(cd $(GIT)/$$repo.git && git push -u origin master) ; \
	done
	git init -q $(GIT)/L.git
	# Not yet, BK no likey
	bk -P fast-export -S | \
		(cd $(GIT)/L.git && git fast-import)
	(cd $(GIT)/L.git ; git remote add origin git@github.com:bitkeeper-scm/little-lang.git ; git checkout -f master)
	for repo in `bk comps`; \
	do	repo=`basename $$repo`; \
		(cd $(GIT)/L.git && git submodule add git@github.com:bitkeeper-scm/$$repo.git $$repo) ; \
	done
	cd $(GIT)/L.git && git commit -m 'Add submodule pointers'
	cd $(GIT)/L.git && git push -u origin master

.PHONY: unix macosx win
