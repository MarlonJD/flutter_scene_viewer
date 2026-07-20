package android.content;

import android.content.pm.PackageManager;

public abstract class Context {
  public abstract PackageManager getPackageManager();
  public abstract String getPackageName();
}
