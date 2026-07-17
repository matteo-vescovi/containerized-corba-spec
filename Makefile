###
# Build specification docs
#

### Setup
# There is very little to set up to run the containerized version of MDSA.
#
# If you wish to change either the location of generated content from a model, or the name of the resulting PDF,
# edit the appropriate values in Makefile.docker (gencondir, pdfnamebase). The rest should be left alone.
#
# If you need to add LaTeX packages, add them one per line to the user-pkgs.txt file, and they will be incorporated
# into your next build.

### Basic use: 'make'
# If a Docker image has not yet been built, that will be done first, then the processing of the LaTeX will begin.
# The resulting PDF (and only that file) will be placed in this directory.
#
### Debugging: `make debug`
# This will show the output of the LaTeX build to help debug.
#
### Using pandoc for Markdown
# To use a pandoc based workflow, use 'make pandoc' instead of 'make'. i.e. `make pandoc build` or `make pandoc all`
#

.PHONY: all build run debug clean help pandoc

help:
	    @echo "Makefile arguments:"
	    @echo ""
	    @echo "tag - Tag to use for Docker image [ defaults to 'latest' ]"
	    @echo ""
	    @echo "Available commands:"
	    @echo "build  - Build the container to process LaTeX"
	    @echo "run    - Process document source files to produce PDF"
		@echo "all    - Build Docker image, run container, process LaTeX [ default action ]"
		@echo "pandoc - Use pandoc specific tool chain in all following commands"
	    @echo "clean  - Remove Docker image"
		@echo "wipe   - Remove Docker image and cache for building images"
		@echo "         NOTE: removes *ALL* build caches from Docker - use forcebuild in most cases"
		@echo ""
		@echo "Commands for debugging:"
		@echo "forcebuild  - Builds image with --no-cache, to force a fresh rebuild"
		@echo "debug       - 'run', but shows debugging output from LaTeX processing"
		@echo "interactive - Builds image and runs container, opens a bash shell for interactive use"
		@echo ""
		@echo "Commands can be chained as needed:"
		@echo "make clean build run"
		@echo "    - Cleans out all products, starts from scratch and produces a PDF using default toolchain"
		@echo "make pandoc build run"
		@echo "    - Build and run a pandoc based toolchain to produce the PDF"

.DEFAULT_GOAL := all

# Tag for Docker image. Override with `make tag=foo`
tag ?= latest

_suffix :=
_image := omg/mdsa:${tag}
_base := texlive/texlive
_basetag := latest-small
_baseimage := ${_base}:${_basetag}

# If you wish to use pandoc by default, set the above _suffix and _image to the values in the following
# rule. Otherwise, `make pandoc <other commands>` will use pandoc as needed.
pandoc:
	$(eval _suffix := .pandoc)
	$(eval _image := omg/mdsa${_suffix}:${tag})
	$(eval _base := pandoc/latex)
	$(eval _basetag := latest-ubuntu)
	$(eval _baseimage := ${_base}:${_basetag})
	@echo Using ${_image}

build: Dockerfile user-pkgs.txt
	@echo Building from ${_baseimage} to ${_image}
	docker build --build-arg BASEIMAGE=${_baseimage} -t ${_image} --file Dockerfile .

forcebuild: Dockerfile user-pkgs.txt
	@echo Forcing build from ${_baseimage} to ${_image}
	docker build --build-arg BASEIMAGE=${_baseimage} -t ${_image} --no-cache --file Dockerfile .

interactive:
	@sed -e 's|ENTRYPOINT .*$$|ENTRYPOINT ["/bin/bash"]|g' Dockerfile > Dockerfile.interactive
	@docker build --build-arg BASEIMAGE=${_baseimage} -t ${_image} --file Dockerfile.interactive .
	@rm Dockerfile.interactive
	@echo
	@echo INTERACTIVE MODE - /app/launch.sh to invoke LaTeX processing, Ctrl-D to exit
	@echo
	@docker run -it -v "${CURDIR}:/source" ${_image}

run: build
	@echo Building PDF
	@docker run --rm -v "${CURDIR}:/source" ${_image}

debug: build
	@echo Debugging PDF run
	docker run --rm -v "${CURDIR}:/source" ${_image} debug

clean:
	@echo Removing image ${_image}
	docker rmi ${_image}

wipe: clean
	@echo Removing _all_ build caches
	docker builder prune -a

all: build run

##########
# Experimental commands below - do not use for production at this time
#
### Generating from a model
# If a file named <SPECACRO>.config is present in this directory, it will be used to drive md2LaTeX.py from the mdsa-tools
# repository, and generate LaTeX files from a MagicDraw model. (Other tool support pending.) Otherwise, this step
# is skipped.

# Where you GeneratedContent will be placed from your model if you're using that mechanism
gencondir := GeneratedContent
${gencondir}:
	mkdir -p "${gencondir}"

# Only generate from the model if there is an appropriate ${specacro}.config file. I.e. UML.config or BPMN.config.
gen: ${gencondir}
	@echo --- Generating from model
	@if [ -f "${specacro}.config" ]; then \
		./mdsa-tools/omgmdsa/md2LaTeX.py --config "${specacro}.config"; \
	else \
		echo "[MDSA] No "${specacro}.config" file, not building from model"; \
	fi

