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

.PHONY: all build run debug check clean help pandoc

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
		@echo "check       - .run., then report undefined references, citations and unprocessed Markdown"
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

# pandoc/latex image tag for `make pandoc`. Override to pin a version, e.g.
# make pandoc_tag=3.11-ubuntu pandoc build run
# Note: in some 'latest' images, pandoc-crossref was built for an older pandoc
# version and prints a warning during conversion. The output is still correct.
pandoc_tag ?= latest-ubuntu

# Optional: TeX Live package repository used by tlmgr during the image build,
# e.g. make texlive_repository=https://mirrors.mit.edu/CTAN/systems/texlive/tlnet
texlive_repository ?=

# Latest commits of the MDSA core and tools, so that a rebuild picks up new versions
# (see Dockerfile). If a lookup fails (e.g. offline), the version recorded in the
# existing image is used, so the cached installation is kept.
git ?= git
_mdsa_url := https://github.com/ObjectManagementGroup
_lsremote = $(shell ${git} ls-remote ${_mdsa_url}/$(1).git HEAD 2>/dev/null | cut -f1)
_imagelabel = $(shell docker image inspect -f '{{index .Config.Labels "$(1)"}}' ${_image} 2>/dev/null)
_version = $(or $(call _lsremote,$(1)),$(call _imagelabel,org.omg.mdsa.$(2).version))

# Optional: additional options for 'docker build', e.g. a layer cache in CI:
# make docker_build_opts="--cache-from type=gha --cache-to type=gha,mode=max --load" pandoc check
docker_build_opts ?=

_buildargs = --build-arg BASEIMAGE=${_baseimage} --build-arg TEXLIVE_REPOSITORY=${texlive_repository} \
	--build-arg MDSA_TOOLS_VERSION=$(call _version,mdsa-tools,tools) \
	--build-arg MDSA_CORE_VERSION=$(call _version,mdsa-omg-core,core) \
	${docker_build_opts}

# Optional: use a local checkout of mdsa-omg-core instead of the one in the image,
# e.g. to test core changes before they are published: make core=../mdsa-omg-core pandoc run
core ?=
_runargs = -v "${CURDIR}:/source" $(if ${core},-v "$(abspath ${core}):/app/mdsa-omg-core:ro")

# If you wish to use pandoc by default, set the above _suffix and _image to the values in the following
# rule. Otherwise, `make pandoc <other commands>` will use pandoc as needed.
pandoc:
	$(eval _suffix := .pandoc)
	$(eval _image := omg/mdsa${_suffix}:${tag})
	$(eval _base := pandoc/latex)
	$(eval _basetag := ${pandoc_tag})
	$(eval _baseimage := ${_base}:${_basetag})
	@echo Using ${_image}

build: Dockerfile user-pkgs.txt
	@echo Building from ${_baseimage} to ${_image}
	docker build ${_buildargs} -t ${_image} --file Dockerfile .

forcebuild: Dockerfile user-pkgs.txt
	@echo Forcing build from ${_baseimage} to ${_image}
	docker build ${_buildargs} -t ${_image} --no-cache --file Dockerfile .

interactive:
	@sed -e 's|ENTRYPOINT .*$$|ENTRYPOINT ["/bin/bash"]|g' Dockerfile > Dockerfile.interactive
	@docker build ${_buildargs} -t ${_image} --file Dockerfile.interactive .
	@rm Dockerfile.interactive
	@echo
	@echo INTERACTIVE MODE - /app/launch.sh to invoke LaTeX processing, Ctrl-D to exit
	@echo
	@docker run -it ${_runargs} ${_image}

run: build
	@echo Building PDF
	@docker run --rm ${_runargs} ${_image}

check: build
	@echo Building and checking PDF
	@docker run --rm ${_runargs} ${_image} check

debug: build
	@echo Debugging PDF run
	docker run --rm ${_runargs} ${_image} debug

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

