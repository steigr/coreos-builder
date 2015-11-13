BID        := $(shell date +%s )
MAINTAINER := Mathias Kaufmann <me@stei.gr>
IMAGE      := coreos

.PHONY: builder releases coreos/*
all: releases clean

builder:
	echo 'from alpine' > Dockerfile
	echo 'run apk add --update squashfs-tools xz curl bash' >> Dockerfile
	echo 'add builder /usr/local/bin/builder' >> Dockerfile
	echo 'entrypoint ["builder"]' >> Dockerfile
	docker build -t $(BID) -f Dockerfile .
	rm Dockerfile

jq:
	curl -sLo jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-osx-amd64
	chmod +x jq

coreos/coreos-%.tar.xz: builder
	$(eval release = $(subst .tar.xz,,$(subst coreos/coreos-,,$@)))
	test -s "$@" || docker run \
		--rm \
		--tty \
		--interactive \
		--volume "$(PWD)/coreos":/target \
		--env TARGET=/target \
		--env TRACE=1 \
		$(BID) \
		$(release)

coreos/README.md:
	cat README.md.template \
	| sed -e 's@%IMAGE%@$(IMAGE)@g' \
	> $@

coreos/Dockerfile:
	echo 'from scratch' > $@
	echo 'maintainer $(MAINTAINER)' >> $@
	echo 'add coreos-$(RELEASE).tar.xz /'>> $@
	echo 'entrypoint ["/usr/lib64/systemd/systemd"]'>> $@
	echo 'env container=docker'>> $@
	echo 'volume ["/usr/share/oem","/home","/var","/etc","/root","/home","/opt","/media","/mnt"]' >> $@

coreos/checkout:
	cd coreos; \
	git pull; \
	git checkout coreos/$(RELEASE) || true
	find coreos -name "coreos-*.tar.xz" -exec git rm '{}' ';'

coreos/commit:
	cd coreos; \
	git add Dockerfile coreos-*.tar.* README.md; \
	git commit -m "CoreOS in Docker $(RELEASE)"; \
	git tag -d coreos/$(RELEASE) || true; \
	git tag -d $(RELEASE) || true; \
	git tag coreos/$(RELEASE) master; \
	git tag $(RELEASE) master


coreos/%:
	$(eval RELEASE := $(subst coreos/,,$@))
	$(MAKE) coreos/checkout RELEASE="$(RELEASE)"
	$(MAKE) coreos/README.md IMAGE="$(IMAGE)/$(RELEASE)"
	$(MAKE) coreos/Dockerfile MAINTAINER="$(MAINTAINER)" RELEASE="$(RELEASE)"
	$(MAKE) coreos/coreos-$(RELEASE).tar.xz
	$(MAKE) coreos/commit RELEASE="$(RELEASE)"

releases: jq
	$(eval RELEASES := $(shell curl -sL https://coreos.com/releases/releases.json | jq -r 'to_entries|.[].key' | sort -r) )
	for release in $(RELEASES); do \
		$(MAKE) coreos/$$release BID=$(BID) IMAGE=$(IMAGE); \
	done

clean-builder:
	docker rmi -f $(BID) || true

clean: clean-builder
	rm -rf jq