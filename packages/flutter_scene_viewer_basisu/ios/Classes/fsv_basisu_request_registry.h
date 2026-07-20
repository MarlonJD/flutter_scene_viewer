#ifndef FSV_BASISU_REQUEST_REGISTRY_H_
#define FSV_BASISU_REQUEST_REGISTRY_H_

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "fsv_basisu_control.h"

namespace fsv_basisu {

enum class FsvCancelStatus { kCancelled, kAlreadyFinished, kUnknownRequest };
enum class FsvFinishDisposition { kSuccess, kCancelled, kDetached };
enum class FsvRegisterFailure {
  kNone,
  kDuplicate,
  kDetached,
  kControlCreationFailed,
};

class FsvDecodeRequestRegistry {
 public:
  struct Entry {
    enum class State { kActive, kCancelled, kFinished, kDetached };

    explicit Entry(uint64_t working_byte_limit)
        : control(std::make_shared<FsvDecodeControl>(working_byte_limit)) {}

    std::shared_ptr<FsvDecodeControl> control;
    State state = State::kActive;
    bool delivered = false;
  };

  std::shared_ptr<Entry> Register(const std::string& request_id,
                                  uint64_t working_byte_limit,
                                  FsvRegisterFailure* failure = nullptr) noexcept;
  FsvCancelStatus Cancel(const std::string& request_id);
  bool ShouldStart(const std::shared_ptr<Entry>& entry) const;
  FsvFinishDisposition Finish(const std::string& request_id,
                              const std::shared_ptr<Entry>& entry);
  bool ClaimDelivery(const std::shared_ptr<Entry>& entry);
  void BeginDetach();
  void DrainAfterWorkers();
  size_t active_count() const;

 private:
  static constexpr size_t kMaxFinishedRequests = 1024;

  mutable std::mutex mutex_;
  std::unordered_map<std::string, std::shared_ptr<Entry>> active_;
  std::unordered_set<std::string> finished_;
  bool detached_ = false;
};

}  // namespace fsv_basisu

#endif  // FSV_BASISU_REQUEST_REGISTRY_H_
