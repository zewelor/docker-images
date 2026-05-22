import "common.just"

# Build all images
build-all: build-sqlite3 build-rsync build-tftp build-ruby build-nvim build-nut

# Test all built images to verify their binaries execute correctly
test-all: test-sqlite3 test-rsync test-tftp test-ruby test-nvim test-nut

# Individual builds
build-sqlite3:
    just sqlite3/

build-rsync:
    just rsync/

build-tftp:
    just tftp/

build-ruby:
    just ruby/

build-nvim:
    just nvim/

build-nut:
    just nut/

# Individual tests
test-sqlite3: build-sqlite3
    docker run --rm sqlite3 --version

test-rsync: build-rsync
    docker run --rm rsync --version

test-tftp: build-tftp
    docker run --rm tftp -V

test-ruby: build-ruby
    docker run --rm ruby /usr/local/bin/ruby --version

test-nvim: build-nvim
    docker run --rm nvim --version

test-nut: build-nut
    docker run --rm --entrypoint /usr/bin/upsc nut -V

