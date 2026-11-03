#include "test_main.h"
#include "gpu/generation_gate.h"
#include <thread>

TEST(GpuGenerationRevokesStaleFramesAndRejectsReplayedInput) {
  gremote::gpu::GenerationGate gate;
  EXPECT_TRUE(!gate.Accepts(0));
  EXPECT_TRUE(gate.Advance(1));
  EXPECT_TRUE(gate.Accepts(1));
  EXPECT_TRUE(!gate.Advance(1));
  EXPECT_TRUE(gate.Advance(3));
  EXPECT_TRUE(!gate.Accepts(1));
  EXPECT_TRUE(!gate.Advance(2));
  EXPECT_TRUE(gate.Accepts(3));
}
TEST(GpuGenerationNeverGoesBackwardsAcrossThreadsOrAfterClose) {
  gremote::gpu::GenerationGate gate;
  std::thread a([&] { gate.Advance(100); });
  std::thread b([&] { gate.Advance(50); });
  a.join(); b.join();
  EXPECT_TRUE(gate.Accepts(100));
  gate.Close(); gate.Close();
  EXPECT_TRUE(!gate.Accepts(100));
  EXPECT_TRUE(!gate.Advance(101));
}
