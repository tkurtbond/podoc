# GNUmakefile - podoc: the program and its tests.
#
# `make` builds podoc under both size models, build/O2/podoc and
# build/OC/podoc. `make test` builds each unit test, test/<Name>Test.Mod,
# under both, runs it and compares its output with test/<Name>Test.expected
# and its standard error with test/<Name>Test.errors (empty if there is no
# such file); then it runs the case tests, test/cases/, with each podoc
# (tools/runcases), and the markdown writer's round trip on the cases
# test/roundtrip.txt names (tools/roundtrip). None of it needs pandoc.
# `make install` installs the podoc built under $(MODEL), -OC by default
# (32-bit INTEGER, 64-bit LONGINT), with tools/subs2yaml, in $(BINDIR),
# and the user documentation and the templates' licence in $(DOCDIR),
# under $(PREFIX), ~/.local by default, or $(DESTDIR)$(PREFIX) for a
# package; `make uninstall` removes them. `make clean` removes build/.
#
# The libraries podoc uses (ArgParser, Ropes, pounicode) are found in
# $(POCLIBDIR), ~/.local/lib/poc by default, where their own makefiles
# install them. It does not follow PREFIX.

POC ?= poc
PREFIX ?= $(HOME)/.local
POCLIBDIR ?= $(HOME)/.local/lib/poc
BINDIR ?= $(PREFIX)/bin
DOCDIR ?= $(PREFIX)/share/doc/podoc
MODEL ?= OC
BUILD := build

# An installed library on POC_LIBRARY_PATH would be taken in place of the
# one in $(POCLIBDIR).
unexport POC_LIBRARY_PATH

MODELS := O2 OC
SRCS := $(wildcard src/*.Mod)
TESTS := $(patsubst test/%.Mod,%,$(wildcard test/*Test.Mod))
CASES := $(wildcard test/cases/*)

.PHONY: all test test-o2 test-oc compare install uninstall clean FORCE
.SECONDEXPANSION:

all: $(MODELS:%=$(BUILD)/%/podoc)

# what poc -version says, rewritten only when it changes, so that what is
# built depends on the compiler
POC_STAMP := $(BUILD)/poc-version

$(POC_STAMP): FORCE
	@mkdir -p $(BUILD)
	@$(POC) -version > $@.new
	@if cmp -s $@.new $@; then rm -f $@.new; else mv $@.new $@; fi

$(BUILD)/%/podoc: $(SRCS) $(POC_STAMP)
	mkdir -p $(BUILD)/$*
	$(POC) -$* -library-path $(POCLIBDIR) -import-path src \
	  -output-dir $(BUILD)/$* -o $@ src/podoc.Mod

test: test-o2 test-oc

# pandoc and podoc side by side (tools/compare), where pandoc is installed
COMPARE_FORMATS ?= json html ms context markdown plain
compare: $(BUILD)/OC/podoc
	tools/compare $(BUILD)/OC/podoc $(BUILD)/compare $(COMPARE_FORMATS)

test-o2: $(TESTS:%=$(BUILD)/O2/test/%.passed) $(BUILD)/O2/cases.passed \
  $(BUILD)/O2/roundtrip.passed
test-oc: $(TESTS:%=$(BUILD)/OC/test/%.passed) $(BUILD)/OC/cases.passed \
  $(BUILD)/OC/roundtrip.passed

# $* is <model>/test/<Test>. A test is built from the sources, in its own
# directory.
$(BUILD)/%.passed: $(SRCS) test/$$(notdir $$*).Mod test/$$(notdir $$*).expected \
  $$(wildcard test/$$(notdir $$*).errors) $(wildcard test/templates/* test/templates/data/templates/*) \
  $(POC_STAMP)
	mkdir -p $(BUILD)/$(dir $*)
	$(POC) -$(firstword $(subst /, ,$*)) -library-path $(POCLIBDIR) \
	  -import-path src -import-path test -output-dir $(BUILD)/$(dir $*) \
	  -o $(BUILD)/$* test/$(notdir $*).Mod
	cd $(BUILD)/$(dir $*) && ./$(notdir $*) > $(notdir $*).out 2> $(notdir $*).err
	diff -u test/$(notdir $*).expected $(BUILD)/$*.out
	diff -u $(or $(wildcard test/$(notdir $*).errors),/dev/null) $(BUILD)/$*.err
	touch $@

$(BUILD)/%/cases.passed: $(BUILD)/%/podoc $(CASES) tools/runcases
	tools/runcases $(BUILD)/$*/podoc $(BUILD)/$*/cases
	touch $@

# the markdown writer's round trip (tools/roundtrip)
$(BUILD)/%/roundtrip.passed: $(BUILD)/%/podoc $(CASES) test/roundtrip.txt tools/roundtrip
	tools/roundtrip $(BUILD)/$*/podoc $(BUILD)/$*/roundtrip
	touch $@

install: $(BUILD)/$(MODEL)/podoc
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(DOCDIR)
	install -m 755 $(BUILD)/$(MODEL)/podoc $(DESTDIR)$(BINDIR)/podoc
	install -m 755 tools/subs2yaml $(DESTDIR)$(BINDIR)/subs2yaml
	install -m 644 README.md LICENSE docs/user/podoc.md \
	  docs/user/differences.md $(DESTDIR)$(DOCDIR)
	install -m 644 data/templates/README $(DESTDIR)$(DOCDIR)/templates-LICENSE

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/podoc $(DESTDIR)$(BINDIR)/subs2yaml
	rm -f $(DESTDIR)$(DOCDIR)/README.md $(DESTDIR)$(DOCDIR)/LICENSE \
	  $(DESTDIR)$(DOCDIR)/podoc.md $(DESTDIR)$(DOCDIR)/differences.md \
	  $(DESTDIR)$(DOCDIR)/templates-LICENSE
	-rmdir $(DESTDIR)$(DOCDIR)

clean:
	rm -rf $(BUILD)
