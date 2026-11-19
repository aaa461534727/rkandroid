/*
 * Copyright 2019 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "stack_manager.h"

#include <stdio.h>
#include <chrono>
#include <future>
#include <queue>

#include "common/bind.h"
#include "module.h"
#include "os/handler.h"
#include "os/log.h"
#include "os/thread.h"
#include "os/wakelock_manager.h"

using ::bluetooth::os::Handler;
using ::bluetooth::os::Thread;
using ::bluetooth::os::WakelockManager;

namespace bluetooth {

namespace {
// [lz200 板级补丁] 原厂 3s 太短: 本板 WiFi/BT 是同一颗 seekwave CP (SDIO),
// BT HAL initialize() 里要跑 skw_start_bt_service (CP 需要重新下载固件 ~2.0s),
// 实测总耗时 > 3s ⇒ ASSERT 崩进程 ⇒ HAL close() 又把整颗 CP 停掉 ⇒ WiFi 一起挂,
// 然后 wifi/BT 就在 "CP 重启 2s" 与 "3s 超时" 之间死循环 (现场见 rk3576_android14 docs/PROGRESS.md 2026-11-19).
// 放宽到 15s: 正常路径 (CP 已在, boot bt 约 10ms) 完全不受影响, 只有需要重下固件时才用得上.
constexpr std::chrono::seconds kStackStartTimeout{15};
constexpr std::chrono::seconds kStackStopTimeout{15};
}  // namespace

void StackManager::StartUp(ModuleList* modules, Thread* stack_thread) {
  management_thread_ = new Thread("management_thread", Thread::Priority::NORMAL);
  handler_ = new Handler(management_thread_);

  WakelockManager::Get().Acquire();

  std::promise<void> promise;
  auto future = promise.get_future();
  handler_->Post(common::BindOnce(&StackManager::handle_start_up, common::Unretained(this), modules, stack_thread,
                                  std::move(promise)));

  auto init_status = future.wait_for(kStackStartTimeout);

  WakelockManager::Get().Release();

  LOG_INFO("init_status == %d", init_status);

  ASSERT_LOG(
      init_status == std::future_status::ready,
      "Can't start stack, last instance: %s",
      registry_.last_instance_.c_str());

  LOG_INFO("init complete");
}

void StackManager::handle_start_up(ModuleList* modules, Thread* stack_thread, std::promise<void> promise) {
  registry_.Start(modules, stack_thread);
  promise.set_value();
}

void StackManager::ShutDown() {
  WakelockManager::Get().Acquire();

  std::promise<void> promise;
  auto future = promise.get_future();
  handler_->Post(common::BindOnce(&StackManager::handle_shut_down, common::Unretained(this), std::move(promise)));

  auto stop_status = future.wait_for(kStackStopTimeout);

  WakelockManager::Get().Release();
  WakelockManager::Get().CleanUp();

  ASSERT_LOG(
      stop_status == std::future_status::ready,
      "Can't stop stack, last instance: %s",
      registry_.last_instance_.c_str());

  handler_->Clear();
  handler_->WaitUntilStopped(std::chrono::milliseconds(2000));
  delete handler_;
  delete management_thread_;
}

void StackManager::handle_shut_down(std::promise<void> promise) {
  registry_.StopAll();
  promise.set_value();
}

}  // namespace bluetooth
