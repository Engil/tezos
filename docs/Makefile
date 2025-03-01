# You can set these variables from the command line.
SPHINXOPTS    = -aE -n
SPHINXBUILD   = poetry run sphinx-build
SPHINXPROJ    = Tezos
SOURCEDIR     = .
BUILDDIR      = _build

DOCGENDIR     = doc_gen
DOCERRORDIR   = $(DOCGENDIR)/errors
DOCRPCDIR     = $(DOCGENDIR)/rpcs

ALPHA_LONG    = ProtoALphaALphaALphaALphaALphaALphaALphaALphaDdp3zK
HANGZHOU_LONG = PtHangzHogokSuiMHemCuowEavgYTP8J5qQ9fQS793MHYFpCY3r
GRANADA_LONG = PtGRANADsDU8R9daYKAgWnQYAJ64omN1o3KMGVCykShA97vQbvV
ACTIVE_LONG = $(GRANADA_LONG)

ALPHA_SHORT    = alpha
GRANADA_SHORT = 010-PtGRANAD
HANGZHOU_SHORT = 011-PtHangzH
ACTIVE_SHORT = $(GRANADA_SHORT)

SCRIPTSDIR		= scripts
CHECKXREFS		= $(SCRIPTSDIR)/check_proto_xrefs.py

all: manuals odoc html

main:
	@${MAKE} -C .. all

manuals: main
    # alpha protocol
	@../tezos-client -protocol $(ALPHA_LONG) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > alpha/tezos-client.html
	@../tezos-baker-$(ALPHA_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > alpha/tezos-baker.html
	@../tezos-endorser-$(ALPHA_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > alpha/tezos-endorser.html
	@../tezos-accuser-$(ALPHA_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > alpha/tezos-accuser.html
    # 011 (Hangzhou) protocol
	@../tezos-client -protocol $(HANGZHOU_LONG) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 011/tezos-client.html
	@../tezos-baker-$(HANGZHOU_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 011/tezos-baker.html
	@../tezos-endorser-$(HANGZHOU_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 011/tezos-endorser.html
	@../tezos-accuser-$(HANGZHOU_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 011/tezos-accuser.html
    # 010 (Granada) protocol
	@../tezos-client -protocol $(GRANADA_LONG) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 010/tezos-client.html
	@../tezos-baker-$(GRANADA_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 010/tezos-baker.html
	@../tezos-endorser-$(GRANADA_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 010/tezos-endorser.html
	@../tezos-accuser-$(GRANADA_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > 010/tezos-accuser.html
    # active (granada) protocol
	@../tezos-client -protocol $(ACTIVE_LONG) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > active/tezos-client.html
	@../tezos-baker-$(ACTIVE_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > active/tezos-baker.html
	@../tezos-endorser-$(ACTIVE_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > active/tezos-endorser.html
	@../tezos-accuser-$(ACTIVE_SHORT) man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > active/tezos-accuser.html
    # generic
	@../tezos-admin-client man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > api/tezos-admin-client.html
	@../tezos-signer man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > api/tezos-signer.html
	@../tezos-codec man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > api/tezos-codec.html
	@../tezos-snoop man -verbosity 3 -format html | sed "s#${HOME}#\$$HOME#g" > api/tezos-snoop.html

.PHONY: odoc
odoc: main
	@cd $$(pwd)/.. ; dune build @doc
	@rm -rf $$(pwd)/_build/api/odoc
	@mkdir -p $$(pwd)/_build/api
	@cp -r $$(pwd)/../_build/default/_doc $$(pwd)/_build/api/odoc
	@sed -e 's/@media only screen and (max-width: 95ex) {/@media only screen and (max-width: 744px) {/' $$(pwd)/_build/api/odoc/_html/odoc.css > $$(pwd)/_build/api/odoc/_html/odoc.css2
	@echo '.toc {position: static}' >> $$(pwd)/_build/api/odoc/_html/odoc.css2
	@echo '.content { margin-left: 4ex }' >> $$(pwd)/_build/api/odoc/_html/odoc.css2
	@echo '@media (min-width: 745px) {.content {margin-left: 4ex}}' >> $$(pwd)/_build/api/odoc/_html/odoc.css2
	@mv -f $$(pwd)/_build/api/odoc/_html/odoc.css2  $$(pwd)/_build/api/odoc/_html/odoc.css

linkcheck:
	$(SPHINXBUILD) -b linkcheck "$(SOURCEDIR)" "$(BUILDDIR)"

.PHONY: redirectcheck
redirectcheck:
	@cd $$(pwd)/.. ; ./src/tooling/lint.sh --check-redirects

# xrefs should be checked:
# - on the active protocol using its numeric name (not the "active" symlink)
# - on each other protocol including alpha, also checking label defs (option -l)
xrefscheck:
	$(CHECKXREFS) 010
	$(CHECKXREFS) -l 011
	$(CHECKXREFS) -l alpha

scriptsindoccheck:
	introduction/test_howtoget.sh install-bin-bionic
	introduction/test_howtoget.sh install-bin-focal
	introduction/test_howtoget.sh install-bin-fedora33
	introduction/test_howtoget.sh install-bin-fedora34
	introduction/test_howtoget.sh install-opam-scratch
	introduction/test_howtoget.sh install-opam-bionic
	introduction/test_howtoget.sh install-opam-focal
	introduction/test_howtoget.sh compile-sources-buster
	#introduction/test_howtoget.sh use-docker # returns 1 (and eats alot of disk)

sanitycheck:
	@if grep -Rq alpha 0*; then					\
		echo "'alpha' occurs in the docs for released protocols:";	\
                grep -R alpha 0*;                                               \
		exit 1;								\
	fi

api/errors.rst: $(DOCERRORDIR)/error_doc.ml
	@cd .. && dune build docs/$(DOCERRORDIR)/error_doc.exe
	../_build/default/docs/$(DOCERRORDIR)/error_doc.exe > api/errors.rst

$(DOCGENDIR)/rpc_doc.exe:
	@cd .. && dune build docs/$(DOCGENDIR)/rpc_doc.exe

rpc: $(DOCGENDIR)/rpc_doc.exe
	@dune exec $(DOCGENDIR)/rpc_doc.exe index "" > active/rpc.rst
	@dune exec $(DOCGENDIR)/rpc_doc.exe index "011" > 011/rpc.rst
	@dune exec $(DOCGENDIR)/rpc_doc.exe index alpha > alpha/rpc.rst
	@dune exec $(DOCGENDIR)/rpc_doc.exe index shell > shell/rpc.rst
	@dune exec $(DOCGENDIR)/rpc_doc.exe acl > user/default-acl.json

$(DOCGENDIR)/p2p_doc.exe:
	@cd .. && dune build docs/$(DOCGENDIR)/p2p_doc.exe

p2p: $(DOCGENDIR)/p2p_doc.exe shell/p2p_usage.rst.inc
	@dune exec $(DOCGENDIR)/p2p_doc.exe < shell/p2p_usage.rst.inc > shell/p2p_api.rst

.PHONY: help Makefile

.PHONY: install-dependencies
install-dependencies:
	@poetry install

# Catch-all target: route all unknown targets to Sphinx using the new
# "make mode" option.  $(O) is meant as a shortcut for $(SPHINXOPTS).
html: Makefile api/errors.rst rpc p2p install-dependencies
	cp ../CHANGES.rst .
	@$(SPHINXBUILD) -b html "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS)

# pylint does not support pyproject.toml configuration for now
# It is configured by ./.pylint.rc
# In pylint, we ignore the following additional errors:
# - C0330: pylint is wrong (https://github.com/psf/black/issues/48)
PYLINTRC?=../.pylintrc
PYLINT=PYLINTRC=${PYLINTRC} poetry run pylint --disable C0330

# pycodestyle does not support pyproject.toml configuration for now
# https://github.com/PyCQA/pydocstyle/issues/447
#
# In pycodestyle we ignore the following additional errors w.r.t to defaults
# (i.e. E121,E123,E126,E226,E24,E704,W503)
# - E203 :: pycodestyle is wrong (https://github.com/psf/black/issues/315)
#           and black takes care of it
# - E231 :: same as E203
#
# Other error codes are detailed at https://www.flake8rules.com/
PYCODESTYLE=poetry run pycodestyle
PYCODESTYLE_OPTIONS=\
	--ignore=E121,E123,E126,E226,E24,E704,W503,E203,E231 \
	--max-line-length=80

PYTHON_SRCS?=conf.py _extensions/*.py scripts/*.py

pylint:
	@echo "Linting with pylint, version:"
	@poetry run pylint --version | sed 's/^/  /'
	$(PYLINT) $(PYTHON_SRCS)

lint_black:
	@echo "Running black formatter as style checker"
	poetry run black --check $(PYTHON_SRCS)

pycodestyle:
	@echo "Linting with pycodestyle version `poetry run pycodestyle --version` (`poetry run which pycodestyle`)"
	$(PYCODESTYLE) $(PYCODESTYLE_OPTIONS) $(PYTHON_SRCS)

lint: pylint pycodestyle lint_black

clean:
	@-rm -Rf "$(BUILDDIR)"
	@-rm -Rf api/errors.rst active/rpc.rst 010/rpc.rst 011/rpc.rst alpha/rpc.rst shell/rpc.rst shell/p2p_api.rst CHANGES.rst
	@-rm -Rf api/tezos-*.html api/tezos-*.txt active/tezos-*.html 010/tezos-*.html 011/tezos-*.html alpha/tezos-*.html
