// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Local native packet transport and externally driven mission clock.
#pragma once
#include <SiliconLogiX/OrbitLab/Core.h>
#include <Transport/TransportComponentAc.hpp>
#include <atomic>
#include <condition_variable>
#include <mutex>
namespace OrbitLab
{
class Transport final : public TransportComponentBase
{
  public:
    explicit Transport(const char *name) : TransportComponentBase(name) {}
    void setTime(double seconds) { m_time = seconds; }
    void command(Fw::ComBuffer &buffer, U32 sequence) { commandOut_out(0, buffer, sequence); }
    void state(const SlxControl &control, const SlxVehicleStatus &vehicle,
               const SlxOrbitStatus &orbit, const SlxAccessWindow *windows, uint32_t count);
    void ready();
    bool settle(bool tick = false);
    void synchronized();

  private:
    std::atomic<double> m_time{0};
    std::atomic<U32> m_dispatched{0};
    std::atomic<int> m_pending{0};
    inline static std::mutex m_output;
    std::mutex m_fenceMutex;
    std::condition_variable m_fenceCondition;
    U32 m_fenceToken = 0;
    U32 m_fenceReceived[2]{};
    bool fence(FwIndexType port);
    void writePacket(const char *kind, const Fw::ComBuffer &packet);
    void telemetryIn_handler(FwIndexType port, FwChanIdType id, Fw::Time &time,
                             Fw::TlmBuffer &value) override;
    void eventIn_handler(FwIndexType port, FwEventIdType id, Fw::Time &time,
                         const Fw::LogSeverity &severity, Fw::LogBuffer &args) override;
    void responseIn_handler(FwIndexType port, FwOpcodeType opcode, U32 sequence,
                            const Fw::CmdResponse &response) override;
    void clockIn_handler(FwIndexType port, Fw::Time &time) override;
    void sequencerCommandIn_handler(FwIndexType port, Fw::ComBuffer &buffer, U32 context) override;
    void sequencerResponseIn_handler(FwIndexType port, FwOpcodeType opcode, U32 sequence,
                                     const Fw::CmdResponse &response) override;
    void queueFenceReturn_handler(FwIndexType port, U32 token) override;
};
} // namespace OrbitLab
