// Silicon LogiX / SLX OrbitLab
// Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
// Author: Marco Pezzullo
// License: Silicon LogiX Evaluation License 1.0. See LICENSE.

/// @file
/// @brief Separate RTEMS power-permission controller with CRC-protected UART frames and timer
/// heartbeat.
#include <bsp.h>
#include <rtems.h>
#include <rtems/version.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static volatile uint32_t heartbeat = 0;
static uint32_t crc32(const char *text)
{
    uint32_t crc = 0xffffffffu;
    for (const unsigned char *p = reinterpret_cast<const unsigned char *>(text); *p; ++p)
    {
        crc ^= *p;
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}
static rtems_task tick_task(rtems_task_argument)
{
    for (;;)
    {
        ++heartbeat;
        rtems_task_wake_after(100);
    }
}
extern "C" rtems_task Init(rtems_task_argument)
{
    rtems_id timer_task;
    rtems_status_code status =
        rtems_task_create(rtems_build_name('E', 'P', 'S', 'T'), 5, RTEMS_MINIMUM_STACK_SIZE * 2,
                          RTEMS_DEFAULT_MODES, RTEMS_DEFAULT_ATTRIBUTES, &timer_task);
    if (status != RTEMS_SUCCESSFUL ||
        rtems_task_start(timer_task, tick_task, 0) != RTEMS_SUCCESSFUL)
    {
        puts("EPS_BOOT_ERROR TIMER_TASK");
        rtems_task_suspend(RTEMS_SELF);
    }
    printf("ORBITLAB_EPS_READY RTEMS %s ABI 1\n", rtems_version());
    fflush(stdout);
    char line[256];
    uint32_t last_sequence = 0;
    while (fgets(line, sizeof(line), stdin))
    {
        line[strcspn(line, "\r\n")] = 0;
        char *checksum_field = strrchr(line, ' ');
        if (!checksum_field || strlen(checksum_field + 1) != 8)
        {
            puts("EPS_ERR FORMAT");
            fflush(stdout);
            continue;
        }
        char *end = nullptr;
        const uint32_t expected = static_cast<uint32_t>(strtoul(checksum_field + 1, &end, 16));
        *checksum_field = 0;
        if (!end || *end || crc32(line) != expected)
        {
            puts("EPS_ERR CRC");
            fflush(stdout);
            continue;
        }
        unsigned sequence, time_ms, energy_j, capacity_j, requested_mw;
        char extra;
        if (sscanf(line, "EPS %u %u %u %u %u %c", &sequence, &time_ms, &energy_j, &capacity_j,
                   &requested_mw, &extra) != 5 ||
            !sequence || sequence <= last_sequence || capacity_j < 10000 || energy_j > capacity_j ||
            requested_mw > 200000)
        {
            puts("EPS_ERR VALIDATION");
            fflush(stdout);
            continue;
        }
        last_sequence = sequence;
        unsigned permitted_mw = requested_mw, flags = 0;
        if (energy_j < capacity_j / 20)
        {
            flags = 1;
            if (permitted_mw > 18000)
                permitted_mw = 18000;
        }
        if (energy_j < capacity_j / 50)
        {
            flags = 3;
            if (permitted_mw > 5000)
                permitted_mw = 5000;
        }
        char response[128];
        snprintf(response, sizeof(response), "EPS_ACK %u %u %u %u %u", sequence, time_ms,
                 permitted_mw, flags, static_cast<unsigned>(heartbeat));
        printf("%s %08lx\n", response, static_cast<unsigned long>(crc32(response)));
        fflush(stdout);
    }
    rtems_task_suspend(RTEMS_SELF);
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CONSOLE_DRIVER
#define CONFIGURE_MAXIMUM_TASKS 4
#define CONFIGURE_MICROSECONDS_PER_TICK 1000
#define CONFIGURE_INIT_TASK_STACK_SIZE (RTEMS_MINIMUM_STACK_SIZE * 8)
#define CONFIGURE_INIT_TASK_ATTRIBUTES RTEMS_FLOATING_POINT
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE
#define CONFIGURE_INIT
#include <rtems/confdefs.h>
