# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.
register_fprime_module(OrbitLab_Top AUTOCODER_INPUTS "${CMAKE_CURRENT_LIST_DIR}/topology.fpp" SOURCES "${CMAKE_CURRENT_LIST_DIR}/Topology.cpp" HEADERS "${CMAKE_CURRENT_LIST_DIR}/OrbitLabTopologyDefs.hpp")
