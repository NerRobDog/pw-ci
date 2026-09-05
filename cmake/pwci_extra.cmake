# pw-ci: re-add sources Nival's blanket exclusions dropped but the client links against,
# plus vendor libs the original CMakeLists never listed. Included right before add_executable.

# --- sources present in the published tree ---
set( ALL_SRCS ${ALL_SRCS}
  ${SRC_DIR}/Game/PF/Server/LobbyPvx/CommonTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatisticsClientTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatisticsCommonTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatisticsDebugTypes.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/GameStatClient.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatClientDiskDispatcher.cpp
  ${SRC_DIR}/Game/PF/Server/Statistic/StatClientHttpDispatcher.cpp
  ${SRC_DIR}/Server/ServerAppBase/NivalService.cpp
  ${SRC_DIR}/Server/Monitoring/PerfCounterProvider/PerfCounter.cpp
  ${SRC_DIR}/Game/PF/HybridServer/RPeered.auto.cpp
  ${SRC_DIR}/pwci_stubs.cpp
)
include_directories( ${SRC_DIR}/Server/Monitoring ${SRC_DIR}/Game/PF/Server )

# --- vendor / tool libs ---
simple_add_library( wbemuuid )
simple_add_library( ${VENDOR}/JsonCpp/lib/Release/JsonCpp )
simple_add_library( ${VENDOR}/libcurl/lib/Release/libcurl )
simple_add_library( ${SRC_DIR}/../Tools/Censor/lib/Release/CensorDll )
