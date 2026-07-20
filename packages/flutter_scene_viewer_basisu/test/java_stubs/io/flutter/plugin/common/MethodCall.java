package io.flutter.plugin.common;

import java.util.Map;

public final class MethodCall {
  public final String method;
  private final Map<String, Object> arguments;

  public MethodCall(String method, Map<String, Object> arguments) {
    this.method = method;
    this.arguments = arguments;
  }

  @SuppressWarnings("unchecked")
  public <T> T argument(String key) {
    return (T) arguments.get(key);
  }
}
