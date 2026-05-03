import "common.just"

# Build all images
build-all: build-sqlite3 build-rsync build-tftp build-ruby build-nvim

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
