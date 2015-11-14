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
	( cd coreos && find . -name "coreos-*.tar.xz" -not -name "coreos-$(release).tar.xz" -exec git rm '{}' ';' )
	test -s "$@" || docker run --rm --tty \
		--volume "$(PWD)/coreos":/target \
		--env TARGET=/target --env TRACE=$(TRACE) \
		$(BID) $(release)
	( cd  "$$(dirname $@)" && git add "$$(basename "$@")")

coreos/README.md:
	cat README.md.template \
	| sed -e 's@%IMAGE%@$(IMAGE)@g' > $@
	( cd coreos && git add README.md )

coreos/Dockerfile:
	echo 'from scratch' > $@
	echo 'maintainer $(MAINTAINER)' >> $@
	echo 'entrypoint ["/usr/lib64/systemd/systemd"]'>> $@
	echo 'env container=docker'>> $@
	echo 'volume ["/usr/share/oem","/home","/var","/etc","/root","/home","/opt","/media","/mnt"]' >> $@
	echo 'add coreos-$(RELEASE).tar.xz /'>> $@
	( cd coreos && git add Dockerfile )

coreos/checkout:
	cd coreos && git reset --hard
	cd coreos && git checkout master
	cd coreos && git pull
	cd coreos && git tag | grep coreos/$(RELEASE) \
	&& git checkout coreos/$(RELEASE) \
	|| echo "New CoreOS Release $(RELEASE)"

coreos/commit:
	cd coreos && git commit -m "CoreOS in Docker $(RELEASE)"
	cd coreos && git tag -d coreos/$(RELEASE) || true
	cd coreos && git tag -d $(RELEASE) || true
	cd coreos && git tag coreos/$(RELEASE)
	cd coreos && git tag $(RELEASE)

coreos/%:
	$(eval RELEASE := $(subst coreos/,,$@))
	$(MAKE) coreos/checkout RELEASE="$(RELEASE)"
	$(MAKE) coreos/README.md IMAGE="$(IMAGE)/$(RELEASE)"
	$(MAKE) coreos/Dockerfile MAINTAINER="$(MAINTAINER)" RELEASE="$(RELEASE)"
	$(MAKE) coreos/coreos-$(RELEASE).tar.xz TRACE=$(TRACE)
	$(MAKE) coreos/commit RELEASE="$(RELEASE)"

releases: jq
	$(eval RELEASES := $(shell curl -sL https://coreos.com/releases/releases.json | jq -r 'to_entries|.[].key' | sort) )
	for release in $(RELEASES); do \
		$(MAKE) coreos/$$release BID=$(BID) IMAGE=$(IMAGE); \
	done

clean-builder:
	docker rmi -f $(BID) || true

clean: clean-builder
	rm -rf jq