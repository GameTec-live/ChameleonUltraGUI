#include "my_application.h"
#include <glib.h>

static gchar *g_self_exe()
{
  g_autoptr(GError) error = nullptr;
  g_autofree gchar *self_exe = g_file_read_link("/proc/self/exe", &error);
  if (error)
  {
    g_critical("g_file_read_link: %s", error->message);
  }
  return g_path_get_dirname(self_exe);
}

int main(int argc, char **argv)
{
  g_autoptr(MyApplication) app = my_application_new();

  g_autofree gchar *self_exe = g_self_exe();
  g_autofree gchar *librecovery_path =
      g_build_filename(self_exe, "lib", "librecovery.so", nullptr);
  g_setenv("LIBRECOVERY_PATH", librecovery_path, 0);

  return g_application_run(G_APPLICATION(app), argc, argv);
}
