package com.marlonjd.flutter_scene_viewer_draco;

import java.util.LinkedHashSet;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

final class FsvDecodeRequestRegistry {
  interface Control {
    void cancel();
    void destroy();
  }

  enum FinishDisposition {
    SUCCESS,
    CANCELLED,
    DETACHED
  }

  static final class Entry {
    enum State {
      ACTIVE,
      CANCELLED,
      FINISHED,
      DETACHED
    }

    final Control control;
    State state = State.ACTIVE;
    boolean delivered;

    Entry(Control control) {
      this.control = control;
    }
  }

  private static final int MAX_FINISHED_REQUESTS = 1024;
  private final Map<String, Entry> active = new LinkedHashMap<>();
  private final Set<String> finished = new LinkedHashSet<>();
  private boolean detached;

  synchronized Entry register(String requestId, Control control) {
    if (detached || active.containsKey(requestId)) {
      return null;
    }
    Entry entry = new Entry(control);
    active.put(requestId, entry);
    return entry;
  }

  synchronized String cancel(String requestId) {
    Entry entry = active.get(requestId);
    if (entry == null) {
      return finished.contains(requestId) ? "alreadyFinished" : "unknownRequest";
    }
    if (entry.state == Entry.State.ACTIVE) {
      entry.state = Entry.State.CANCELLED;
      entry.control.cancel();
    }
    return entry.state == Entry.State.FINISHED
        ? "alreadyFinished"
        : "cancelled";
  }

  synchronized FinishDisposition finish(String requestId, Entry entry) {
    if (active.get(requestId) != entry) {
      return detached
          ? FinishDisposition.DETACHED
          : FinishDisposition.CANCELLED;
    }
    FinishDisposition disposition;
    if (detached || entry.state == Entry.State.DETACHED) {
      disposition = FinishDisposition.DETACHED;
    } else if (entry.state == Entry.State.CANCELLED) {
      disposition = FinishDisposition.CANCELLED;
    } else {
      disposition = FinishDisposition.SUCCESS;
    }
    entry.state = Entry.State.FINISHED;
    entry.control.destroy();
    active.remove(requestId);
    if (!detached) {
      finished.add(requestId);
      while (finished.size() > MAX_FINISHED_REQUESTS) {
        String oldest = finished.iterator().next();
        finished.remove(oldest);
      }
    }
    return disposition;
  }

  synchronized boolean shouldStart(Entry entry) {
    return !detached && entry.state == Entry.State.ACTIVE;
  }

  synchronized boolean claimDelivery(Entry entry) {
    if (detached || entry.delivered) {
      return false;
    }
    entry.delivered = true;
    return true;
  }

  synchronized void beginDetach() {
    if (detached) {
      return;
    }
    detached = true;
    for (Entry entry : active.values()) {
      if (entry.state == Entry.State.ACTIVE) {
        entry.state = Entry.State.DETACHED;
        entry.control.cancel();
      } else if (entry.state == Entry.State.CANCELLED) {
        entry.state = Entry.State.DETACHED;
      }
    }
  }

  synchronized void drainAfterWorkers() {
    for (Entry entry : active.values()) {
      entry.control.destroy();
    }
    active.clear();
    finished.clear();
  }

  synchronized int activeCount() {
    return active.size();
  }
}
