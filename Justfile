import "common.just"

# Build all images
build-all: build-sqlite3 build-rsync build-tftp build-postgres-init build-ruby

# Individual builds
build-sqlite3:
    just sqlite3/

build-rsync:
    just rsync/

build-tftp:
    just tftp/

build-postgres-init:
    just postgres-init/

build-ruby:
    just ruby/
