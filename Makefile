	# Since we rely on paths relative to the makefile location, abort if make isn't being run from there.
$(if $(findstring /,$(MAKEFILE_LIST)),$(error Please only invoke this makefile from the directory it resides in))
	# Add the local npm packages' bin folder to the PATH, so that `make` can find them, when invoked directly.
	# Note that rather than using `$(npm bin)` the 'node_modules/.bin' path component is hard-coded, so that invocation works even from an environment
	# where npm is (temporarily) unavailable due to having deactivated an nvm instance loaded into the calling shell in order to avoid interference with tests.
export PATH := $(shell printf '%s' "$$PWD/node_modules/.bin:$$PATH")
	# The list of all supporting utilities, installed with `npm install`.
UTILS := replace semver
	# Make sure that all required utilities can be located.
UTIL_CHECK := $(or $(shell PATH="$(PATH)" which $(UTILS) >/dev/null && echo 'ok'),$(error Did you forget to run `npm install` after cloning the repo? At least one of the required supporting utilities not found: $(UTILS)))
	# The files that need updating when incrementing the version number.
VERSIONED_FILES := swivm.sh install.sh README.md package.json


# Default target (by virtue of being the first non '.'-prefixed in the file).
.PHONY: _no-target-specified
_no-target-specified:
	$(error Please specify the target to make - `make list` shows targets. Alternatively, use `npm test` to run the default tests; `npm run` shows all tests)

# Lists all targets defined in this makefile.
.PHONY: list
list:
	@$(MAKE) -pRrn : -f $(MAKEFILE_LIST) 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | egrep -v -e '^[^[:alnum:]]' -e '^$@$$' | sort

.PHONY: _ensure-tag
_ensure-tag:
ifndef TAG
	$(error Please invoke with `make TAG=<new-version> release`, where <new-version> is either an increment specifier (patch, minor, major, prepatch, preminor, premajor, prerelease), or an explicit major.minor.patch version number)
endif

# Ensures that the git workspace is clean.
.PHONY: _ensure-clean
_ensure-clean:
	@[ -z "$$(git status --porcelain --untracked-files=no || echo err)" ] || { echo "Workspace is not clean; please commit changes first." >&2; exit 2; }

# Makes a release; invoke with `make TAG=<versionOrIncrementSpec> release`.
.PHONY: release
release: _ensure-tag _ensure-clean
	@old_ver=`git describe --abbrev=0 --tags --match 'v[0-9]*.[0-9]*.[0-9]*'` || { echo "Failed to determine current version." >&2; exit 1; }; old_ver=$${old_ver#v}; \
	 new_ver=`echo "$(TAG)" | sed 's/^v//'`; new_ver=$${new_ver:-patch}; \
	 if printf "$$new_ver" | grep -q '^[0-9]'; then \
	   semver "$$new_ver" >/dev/null || { echo 'Invalid version number specified: $(TAG) - must be major.minor.patch' >&2; exit 2; }; \
	   semver -r "> $$old_ver" "$$new_ver" >/dev/null || { echo 'Invalid version number specified: $(TAG) - must be HIGHER than current one.' >&2; exit 2; } \
	 else \
	   new_ver=`semver -i "$$new_ver" "$$old_ver"` || { echo 'Invalid version-increment specifier: $(TAG)' >&2; exit 2; } \
	 fi; \
	 printf "=== Bumping version **$$old_ver** to **$$new_ver** before committing and tagging:\n=== TYPE 'proceed' TO PROCEED, anything else to abort: " && read response && [ "$$response" = 'proceed' ] || { echo 'Aborted.' >&2; exit 2; };  \
	 replace "$$old_ver" "$$new_ver" -- $(VERSIONED_FILES) && \
	 git commit -m "v$$new_ver" $(VERSIONED_FILES) && \
	 git tag -a -m "v$$new_ver" "v$$new_ver"
