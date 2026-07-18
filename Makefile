.PHONY: native native-release native-test native-header native-clean

native:
	scripts/native/build.sh Debug

native-release:
	scripts/native/build.sh Release

native-test:
	scripts/native/test.sh

native-header:
	scripts/native/header.sh

native-clean:
	scripts/native/clean.sh
