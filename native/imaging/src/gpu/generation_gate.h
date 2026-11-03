#pragma once
#include <atomic>
#include <cstdint>

namespace gremote::gpu {
// Advance is safe from the platform/UI thread. EGL operations stay on the
// renderer thread; a cancelled job must pass this gate before presentation.
class GenerationGate {
 public:
  bool Advance(uint64_t generation) {
    if (!generation || closed_.load()) return false;
    auto previous = latest_.load();
    while (generation > previous) {
      if (latest_.compare_exchange_weak(previous, generation)) return !closed_.load();
    }
    return false;
  }
  bool Accepts(uint64_t generation) const {
    return generation && !closed_.load() && latest_.load() == generation;
  }
  void Close() { closed_.store(true); }
 private:
  std::atomic<uint64_t> latest_{0};
  std::atomic<bool> closed_{false};
};
}  // namespace gremote::gpu
