package android.content.pm;

public abstract class PackageManager {
  public static final int GET_META_DATA = 128;

  public static class NameNotFoundException extends Exception {}

  public abstract ApplicationInfo getApplicationInfo(String name, int flags)
      throws NameNotFoundException;
}
