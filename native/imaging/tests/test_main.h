// Minimal single-header test harness for the imaging core.
#pragma once

#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace gremote_test {

struct Case {
  const char* name;
  std::function<void()> body;
};

inline std::vector<Case>& Registry() {
  static std::vector<Case> cases;
  return cases;
}

inline int& Failures() {
  static int failures = 0;
  return failures;
}

struct Registrar {
  Registrar(const char* name, std::function<void()> body) {
    Registry().push_back({name, std::move(body)});
  }
};

inline void Fail(const char* file, int line, const std::string& message) {
  ++Failures();
  std::fprintf(stderr, "  FAIL %s:%d: %s\n", file, line, message.c_str());
}

inline int RunAll() {
  int failed_cases = 0;
  for (const auto& test_case : Registry()) {
    const int before = Failures();
    test_case.body();
    const bool ok = Failures() == before;
    if (!ok) ++failed_cases;
    std::printf("[%s] %s\n", ok ? " OK " : "FAIL", test_case.name);
  }
  std::printf("%zu tests, %d failed\n", Registry().size(), failed_cases);
  return failed_cases == 0 ? 0 : 1;
}

}  // namespace gremote_test

#define GREMOTE_CONCAT_INNER(a, b) a##b
#define GREMOTE_CONCAT(a, b) GREMOTE_CONCAT_INNER(a, b)

#define TEST(name)                                                    \
  static void name();                                                 \
  static gremote_test::Registrar GREMOTE_CONCAT(registrar_, name)(#name, name); \
  static void name()

#define EXPECT_TRUE(condition)                                         \
  do {                                                                 \
    if (!(condition)) gremote_test::Fail(__FILE__, __LINE__, #condition); \
  } while (0)

#define EXPECT_EQ(actual, expected)                                        \
  do {                                                                     \
    const auto gremote_a = (actual);                                          \
    const auto gremote_e = (expected);                                        \
    if (!(gremote_a == gremote_e)) {                                             \
      gremote_test::Fail(__FILE__, __LINE__,                                  \
                      std::string(#actual " == " #expected " (got ") +     \
                          std::to_string(gremote_a) + ", want " +             \
                          std::to_string(gremote_e) + ")");                   \
    }                                                                      \
  } while (0)

#define EXPECT_NEAR(actual, expected, tolerance)                            \
  do {                                                                      \
    const double gremote_a = static_cast<double>(actual);                      \
    const double gremote_e = static_cast<double>(expected);                    \
    if (!(std::fabs(gremote_a - gremote_e) <= (tolerance))) {                     \
      gremote_test::Fail(__FILE__, __LINE__,                                   \
                      std::string(#actual " ~ " #expected " (got ") +       \
                          std::to_string(gremote_a) + ", want " +              \
                          std::to_string(gremote_e) + ")");                    \
    }                                                                       \
  } while (0)
