PYTHON?=python
TESTOPTS?=
REPO = git://github.com/cython/cython.git
PROGRAM?=cython
PACKAGE?=${PYTHON}-$(PROGRAM)
VERSION?=$(shell sed -n s/[[:space:]]*Version:[[:space:]]*//p $(PACKAGE).spec)


MANYLINUX_IMAGE_X86_64=quay.io/pypa/manylinux1_x86_64
MANYLINUX_IMAGE_686=quay.io/pypa/manylinux1_i686

all:    local

build:
	$(PYTHON) setup.py build

local:
	${PYTHON} setup.py build_ext --inplace

install:
	$(PYTHON) setup.py install --skip-build

dist:
	$(PYTHON) setup.py sdist

sources: clean
	@git archive --format=tar --prefix="$(PROGRAM)-$(VERSION)/" \
		$(shell git rev-parse --verify HEAD) | gzip > "$(PROGRAM)-$(VERSION).tar.gz"

srpm: sources
	rpmbuild -bs --define "_sourcedir $(CURDIR)" \
		--define "_srcrpmdir $(CURDIR)" $(PACKAGE).spec


TMPDIR = .repo_tmp
.git: .gitrev
	rm -rf $(TMPDIR)
	git clone -n $(REPO) $(TMPDIR)
	cd $(TMPDIR) && git reset -q "$(shell cat .gitrev)"
	mv $(TMPDIR)/.git .
	rm -rf $(TMPDIR)
	git ls-files -d | xargs git checkout --

repo: .git


clean:
	@echo Cleaning Source
	@rm -rf build dist $(PROGRAM).egg-info $(PROGRAM)-*.tar.gz *.egg *.src.rpm
	@rm -f *.py[co] */*.py[co] */*/*.py[co] */*/*/*.py[co]
	@rm -f *.so */*.so */*/*.so
	@rm -f *.pyd */*.pyd */*/*.pyd
	@rm -f *~ */*~ */*/*~
	@rm -f core */core
	@rm -f Cython/Compiler/*.c
	@rm -f Cython/Plex/*.c
	@rm -f Cython/Tempita/*.c
	@rm -f Cython/Runtime/refnanny.c
	@(cd Demos; $(MAKE) clean)

testclean:
	rm -fr BUILD TEST_TMP

test:	testclean
	${PYTHON} runtests.py -vv ${TESTOPTS}

s5:
	$(MAKE) -C Doc/s5 slides

wheel_manylinux: wheel_manylinux64 wheel_manylinux32

wheel_manylinux32 wheel_manylinux64: dist/Cython-$(VERSION).tar.gz
	echo "Building wheels for Cython $(VERSION)"
	mkdir -p wheelhouse_$(subst wheel_,,$@)
	time docker run --rm -t \
		-v $(shell pwd):/io \
		-e CFLAGS="-O3 -g0 -mtune=generic -pipe -fPIC" \
		-e LDFLAGS="$(LDFLAGS) -fPIC" \
		-e WHEELHOUSE=wheelhouse_$(subst wheel_,,$@) \
		$(if $(patsubst %32,,$@),$(MANYLINUX_IMAGE_X86_64),$(MANYLINUX_IMAGE_686)) \
		bash -c 'for PYBIN in /opt/python/*/bin; do \
		    $$PYBIN/python -V; \
		    { $$PYBIN/pip wheel -w /io/$$WHEELHOUSE /io/$< & } ; \
		    done; wait; \
		    for whl in /io/$$WHEELHOUSE/Cython-$(VERSION)-*-linux_*.whl; do auditwheel repair $$whl -w /io/$$WHEELHOUSE; done'

.PHONY: build install dist sources srpm clean
