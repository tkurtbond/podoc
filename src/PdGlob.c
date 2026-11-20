/* PdGlob's part in C: reading a directory and telling what kind of
   file a name is, with POSIX opendir, readdir and stat. */

#include <dirent.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>

/* The directory name open for reading, or 0 */
void *pdglob_open(const char *name)
{
  return opendir(name);
}

/* The name of the next entry of the directory d in buf, of len bytes,
   "." and ".." left out: its length, or -1 at the end. A name that
   does not fit is skipped. */
int32_t pdglob_next(void *d, char *buf, int32_t len)
{
  struct dirent *e;
  size_t n;

  for (;;) {
    e = readdir((DIR *)d);
    if (e == NULL) return -1;
    if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
    n = strlen(e->d_name);
    if (n < (size_t)len) {
      memcpy(buf, e->d_name, n + 1);
      return (int32_t)n;
    }
  }
}

void pdglob_close(void *d)
{
  closedir((DIR *)d);
}

/* What the file name is: 0 missing, 1 a file that is not a directory,
   2 a directory; a symbolic link is followed when follow is not 0 */
int32_t pdglob_kind(const char *name, int32_t follow)
{
  struct stat st;

  if ((follow ? stat(name, &st) : lstat(name, &st)) != 0) return 0;
  return S_ISDIR(st.st_mode) ? 2 : 1;
}
