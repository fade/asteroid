ROOT_DIR:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
PACKAGE=asteroid
PACKAGEUTILS=asteroid.app-utils
OUT=asteroid
ENTRY=-main

.PHONY: $(OUT)
$(OUT): clean
	sbcl --load build-asteroid.lisp

quicklisp-manifest.txt: *.asd
	sbcl --non-interactive \
		--eval '(push #P"$(ROOT_DIR)/" asdf:*central-registry*)'\
		--eval '(ql:quickload "$(PACKAGE)")'\
		--eval '(ql:write-asdf-manifest-file "quicklisp-manifest.txt")'

clean:
	rm -f *.fasl $(OUT) buildapp quicklisp-manifest.txt
