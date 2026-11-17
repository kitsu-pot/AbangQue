#include "TimeSync.h"
std::atomic<bool> TimeSync::synchronized_{false};
std::atomic<uint32_t> TimeSync::synchronizedAt_{0};
