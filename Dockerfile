# FROM python:3.10-slim
ARG BASEIMAGE=texlive/texlive:latest-small
FROM ${BASEIMAGE} AS mdsa-base

# Install necessary build tools and dependencies
RUN apt-get update && apt-get install -y \
  build-essential \
  make \
  git \
  latexmk \
  python3-full \
  python3-pip \
  inkscape \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN python3 -m venv venv
RUN . venv/bin/activate
ENV PATH="/app/venv/bin:${PATH}"

# Set working directory (set up user account?)
WORKDIR /app

# Optional: fixed TeX Live package repository (CTAN mirror or tlnet archive)
# instead of the mirror.ctan.org redirector, e.g.
#   make texlive_repository=https://mirrors.mit.edu/CTAN/systems/texlive/tlnet
ARG TEXLIVE_REPOSITORY=
RUN if [ -n "${TEXLIVE_REPOSITORY}" ]; then tlmgr option repository "${TEXLIVE_REPOSITORY}"; fi

# tlmgr refuses to install packages if the repository requires a newer tlmgr
# ("tlmgr itself needs to be updated"), e.g. with an older cached base image.
# Uses the same repository as 'tlmgr install' below; does nothing if up to date.
RUN tlmgr update --self

# Get the necessary LaTeX piece for MDSA templates
RUN tlmgr install \
  appendix \
  changebar \
  catchfile \
  changepage \
  courier \
  csquotes \
  draftwatermark \
  enumitem \
  everypage \
  helvetic \
  ifmtarg \
  import \
  marginnote \
  ragged2e \
  soul \
  svg \
  tabularray \
  ninecolors \
  times \
  titlesec \
  todonotes \
  transparent \
  varwidth \
  xifthen \
  xstring

FROM mdsa-base AS mdsa

# Install the MDSA core and tools
# MDSA_TOOLS_VERSION and MDSA_CORE_VERSION are the latest commits of the two
# repositories, looked up by the Makefile with 'git ls-remote'. Docker re-runs a
# clone only when its value changes, so new versions are picked up without
# 'make forcebuild', and the cached clone is reused otherwise. The values are kept
# as image labels, so the Makefile can reuse them if a lookup fails (e.g. offline).
ARG MDSA_TOOLS_VERSION=
RUN echo "mdsa-tools ${MDSA_TOOLS_VERSION}" && git clone --depth 1 https://github.com/ObjectManagementGroup/mdsa-tools.git ./mdsa-tools
RUN cd ./mdsa-tools ; pip --no-cache-dir install -e . ; cd ..
ARG MDSA_CORE_VERSION=
RUN echo "mdsa-omg-core ${MDSA_CORE_VERSION}" && git clone --depth 1 https://github.com/ObjectManagementGroup/mdsa-omg-core.git ./mdsa-omg-core
LABEL org.omg.mdsa.tools.version="${MDSA_TOOLS_VERSION}" org.omg.mdsa.core.version="${MDSA_CORE_VERSION}"

# Set up latexmk / texliveonfly integration
RUN <<EOF cat > /app/.latexmkrc
# \$pdflatex = 'texliveonfly %O %S';  # Use texliveonfly for LaTeX compilation
# \$latex = 'texliveonfly %O %S';  # Use texliveonfly for LaTeX compilation
# \$pdf = 'texliveonfly %O %S';  # Use texliveonfly for LaTeX compilation
\$commands = 1;
\$diagnostics = 1;
# \$pdf_mode = 1;  # Set to 1 for PDF output
# \$bibtex_use = 1;
# \$out_dir = '/source';
# \$aux_dir = '.';
EOF

# USER ADDED PACKAGES GO HERE
# This is until texliveonfly is working with latexmk...
COPY user-pkgs.txt /app/user-pkgs.txt

RUN <<EOF cat > /app/install-tex-pkgs.sh
REQUIREMENTS="/app/user-pkgs.txt"
installed=\$(tlmgr list --only-installed --data name)
for pkg in \$(cat \$REQUIREMENTS | grep -v ^#); do
    if echo "\$installed" | grep -q "\$pkg"; then
        echo "\$pkg is already installed, skipping."
        continue
    fi
    tlmgr install "\$pkg"
done
EOF
RUN sed -i 's/\r//' /app/install-tex-pkgs.sh
RUN chmod u+x /app/install-tex-pkgs.sh
RUN /app/install-tex-pkgs.sh
RUN tlmgr path add

# Set up launcher to pull in Makefile and latexmk setup
RUN <<EOF cat > /app/launch.sh
#!/bin/bash
cp "/source/Makefile.mdsa" ./Makefile
# cp "./.latexmkrc" "./build/.latexmkrc"
make \$@
EOF
RUN sed -i 's/\r//' /app/launch.sh
RUN chmod ug+x /app/launch.sh

# Default command
ENTRYPOINT ["/app/launch.sh"]
