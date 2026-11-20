# GNUmakefile - podoc: the program and its tests.
#
# `make` builds podoc under both size models, build/O2/podoc and
# build/OC/podoc. `make test` builds each unit test, test/<Name>Test.Mod,
# under both, runs it and compares its output with test/<Name>Test.expected
# and its standard error with test/<Name>Test.errors (empty if there is no
# such file); then it runs the case tests, test/cases/, with each podoc
# (tools/runcases). Neither needs pandoc. `make clean` removes build/.
#
# The libraries podoc uses (ArgParser, Ropes, pounicode) are found in
# $(POCLIBDIR), ~/.local/lib/poc by default, where their own makefiles
# install them.

POC ?= poc
PREFIX ?= $(HOME)/.local
POCLIBDIR ?= $(PREFIX)/lib/poc
BUILD := build

# An installed library on POC_LIBRARY_PATH would be taken in place of the
# one in $(POCLIBDIR).
unexport POC_LIBRARY_PATH

MODELS := O2 OC
SRCS := $(wildcard src/*.Mod)
TESTS := $(patsubst test/%.Mod,%,$(wildcard test/*Test.Mod))
CASES := $(wildcard test/cases/*)

.PHONY: all test test-o2 test-oc clean FORCE
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

test-o2: $(TESTS:%=$(BUILD)/O2/test/%.passed) $(BUILD)/O2/cases.passed
test-oc: $(TESTS:%=$(BUILD)/OC/test/%.passed) $(BUILD)/OC/cases.passed

# $* is <model>/test/<Test>. A test is built from the sources, in its own
# directory.
$(BUILD)/%.passed: $(SRCS) test/$$(notdir $$*).Mod test/$$(notdir $$*).expected \
  $$(wildcard test/$$(notdir $$*).errors) $(POC_STAMP)
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

clean:
	rm -rf $(BUILD)
